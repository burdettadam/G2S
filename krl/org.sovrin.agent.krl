ruleset org.sovrin.agent {
  meta {
    use module org.sovrin.agent_message alias a_msg
    use module io.picolabs.wrangler alias wrangler
    shares __testing, agent_Rx, connection
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      , { "name": "agent_Rx" }
      , { "name": "connection", "args": [ "key" ] }
      ] , "events":
      [ { "domain": "sovrin", "type": "need_invitation", "attrs": [ "auto_accept" ] }
      , { "domain": "sovrin", "type": "new_invitation", "attrs": [ "url" ] }
      , { "domain": "sovrin", "type": "trust_ping_requested" }
      , { "domain": "sovrin", "type": "send_basicmessage", "attrs": [ "their_vk", "content" ] }
      ]
    }
    agent_Rx = function(){
      wrangler:channel("agent")
    }
    connection = function(key){
      ent:connections
    }
    sEp = function(eci,eid,e_d,e_t){
      d = e_d || "sovrin";
      t = e_t || "new_message";
      <<#{meta:host}/sky/event/#{eci}/#{eid}/#{d}/#{t}>>
    }
    invitation = function(){
      uKR = agent_Rx();
      eci = uKR{"id"};
      im = a_msg:connInviteMap(
        ent:label,
        null, // @id
        uKR{["sovrin","indyPublic"]},
        sEp(eci)
      );
      ep = <<#{meta:host}/sky/cloud/#{eci}/org.sovrin.agent.ui/html.html>>;
      ep + "?c_i=" + math:base64encode(im.encode())
    }
  }
//
// generate invitations
//
  rule create_invitation {
    select when sovrin need_invitation
    pre {
      the_invitation = invitation()
      im = the_invitation
        .split("c_i=").klog("split")
        [1].klog("tail")
        .math:base64decode().klog("base64decode")
        .decode().klog("decode")
      timestamp = time:now()
      auto_accept = event:attr("auto_accept") => true | false
      record = { "invitation": im, "auto_accept": auto_accept }
    }
    send_directive("_txt",{"content":the_invitation})
    fired {
      ent:created_invitations{timestamp} := record
    }
  }
//
// accept invitation
//
  rule accept_invitation {
    select when sovrin new_invitation url re#(http.+)# setting(url)
    pre {
      qs = url.split("?").tail().join("?").klog("qs")
      args = qs.split("&").klog("args")
        .map(function(x){x.split("=")}).klog("mapped")
        .collect(function(x){x[0]}).klog("collected")
        .map(function(x){x[0][1]}).klog("flattened")
      c_i = args{"c_i"}.klog("c_i")
      im = math:base64decode(c_i).decode().klog("im")
      chann = agent_Rx()
      my_did = chann{"id"}.klog("my_did")
      my_vk = chann{["sovrin","indyPublic"]}.klog("my_vk")
      rm = a_msg:connReqMap(
        label,
        my_did,
        my_vk,
        sEp(my_did)
      ).klog("rm")
      reqURL = im{"serviceEndpoint"}.klog("reqURL")
      packedBody = indy:pack(
        rm.encode().klog("rm encoded"),
        im{"recipientKeys"}.klog("key"),
        my_did
      ).klog("packedBody")
    }
    fired {
      ent:connReq := ent:connReq.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "connReq" + ent:connReq, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": reqURL, "packedMessage": packedBody
      }
    }
  }
//
// receive messages
//
  rule route_new_message {
    select when sovrin new_message protected re#(.*)# setting(protected)
    pre {
      tolog = klog(event:attrs.keys(),"event:attrs.keys()")
      outer = math:base64decode(protected).decode()
        .klog("outer")
      kids = outer{"recipients"}
        .map(function(x){x{["header","kid"]}})
        .klog("kids")
      my_vk = wrangler:channel(meta:eci){["sovrin","indyPublic"]}
      sanity = (kids >< my_vk)
        .klog("sanity")
      all = indy:unpack(event:attrs,meta:eci).klog("all")
      their_key = all{"sender_key"}.klog("their_key")
      my_key = all{"recipient_key"}.klog("my_key")
      msg = all{"message"}.decode()
      msg_type = msg{"@type"}.klog("msg_type")
      event_type = a_msg:specToEventType(msg_type)
    }
    if event_type then
      send_directive("message routed",{"event_type":event_type})
    fired {
      raise sovrin event event_type attributes all.put("message",msg)
    }
  }
//
// basicmessage/message
//
  rule handle_basicmessage_message {
    select when sovrin basicmessage_message
    pre {
      msg = event:attr("message")
      expected_reply = msg{"content"}
        .extract(re#Reply with: (.+)#)
        .head()
        .klog("expected_reply")
      bm = a_msg:basicMsgMap(expected_reply)
        .klog("bm")
      their_key = event:attr("sender_key")
      pm = indy:pack(bm.encode(),[their_key],meta:eci)
        .klog("packed message")
      se = ent:endpoints{"their_key"} || "http://localhost:3000/indy"
    }
    if expected_reply && se then noop()
    fired {
      ent:basicMsg := ent:basicMsg.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "basicMsg" + ent:basicMsg, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": se, "packedMessage": pm
      }
    }
  }
//
// connections/request
//
rule handle_connections_request {
    select when sovrin connections_request
    pre {
      msg = event:attr("message")
      req_id = msg{"@id"}.klog("req_id")
      connection = msg{"connection"}.klog("connection")
      publicKeys = connection{["DIDDoc","publicKey"]}
        .map(function(x){x{"publicKeyBase58"}}).klog("publicKeys")
      se = connection{["DIDDoc","service"]}.head(){"serviceEndpoint"}.klog("se")
      chann = agent_Rx()
      my_did = chann{"id"}.klog("my_did")
      my_vk = chann{["sovrin","indyPublic"]}.klog("my_vk")
      endpoint = sEp(my_did).klog("endpoint")
      rm = a_msg:connResMap(req_id, my_did, my_vk, endpoint)
        .klog("response message")
      pm = indy:pack(rm.encode(),publicKeys,meta:eci)
        .klog("packed message")
      c = {
        "label": msg{"label"},
        "my_did": my_did,
        "their_did": connection{"DID"},
        "their_vk": publicKeys.head(),
        "their_endpoint": se
      }.klog("c")
    }
    fired {
      ent:connections := ent:connections.defaultsTo([]).append(c);
      ent:connRes := ent:connRes.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "connRes" + ent:connRes, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": se, "packedMessage": pm
      }
    }
  }
//
// connections/response
//
  rule handle_connections_response {
    select when sovrin connections_response
    pre {
      msg = event:attr("message")
      verified = a_msg:verify_signatures(msg)
        .klog("verified")
      connection = verified{"connection"}
        .klog("connection")
      service = connection && connection{["DIDDoc","service"]}
        .filter(function(x){x{"type"}=="IndyAgent"})
        .head()
        .klog("service")
    }
    if service then noop()
    fired {
      ent:se{service{"recipientKeys"}.head()} := service{"serviceEndpoint"}
    }
  }
//
// trust_ping/ping
//
  rule handle_trust_ping_request {
    select when sovrin trust_ping_ping
    pre {
      msg = event:attr("message")
      rm =a_msg:trustPingResMap(msg{"@id"})
        .klog("response message")
      their_key = event:attr("sender_key")
      pm = indy:pack(rm.encode(),[their_key],meta:eci)
        .klog("packed message")
      se = ent:endpoints{"their_key"} || "http://localhost:3000/indy"
      may_respond = msg{"response_requested"} == false => false | true
    }
    if may_respond then http:post(se,body=pm) setting(http_response)
    fired {
/*
      ent:pingRes := ent:pingRes.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "pingRes" + ent:pingRes, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": se, "packedMessage": pm
      }
*/
    }
    finally {
      ent:trust_ping_vk := their_key
    }
  }
//
// trust_ping/ping_response
//
  rule handle_trust_ping_ping_response {
    select when sovrin trust_ping_ping_response
  }
//
// initiate trust ping
//
  rule initiate_trust_ping {
    select when sovrin trust_ping_requested
    pre {
      rm = a_msg:trustPingMap()
      pm = indy:pack(
        rm.encode(),
        [ent:trust_ping_vk],
        agent_Rx(){"id"}
      )
      se = ent:endpoints{"their_key"} || "http://localhost:3000/indy"
    }
    fired {
      ent:pingReq := ent:pingReq.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "pingReq" + ent:pingReq, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": se, "packedMessage": pm
      }
    }
  }
//
// initiate basicmessage
//
  rule initiate_basicmessage {
    select when sovrin send_basicmessage
    pre {
      their_key = event:attr("their_vk")
      content = event:attr("content")
      bm = a_msg:basicMsgMap(content)
        .klog("bm")
      pm = indy:pack(bm.encode(),[their_key],agent_Rx(){"id"})
        .klog("packed message")
      se = ent:endpoints{"their_key"} || "http://localhost:3001/indy"
    }
    http:post(se,body=pm) setting(http_response)
  }
}

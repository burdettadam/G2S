ruleset org.sovrin.agent {
  meta {
    use module org.sovrin.agent_message alias a_msg
    use module io.picolabs.wrangler alias wrangler
    shares __testing, agent_Rx, ui
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      , { "name": "agent_Rx" }
      ] , "events":
      [ { "domain": "sovrin", "type": "send_basicmessage", "attrs": [ "their_vk", "content" ] }
      ]
    }
    agent_Rx = function(){
      wrangler:channel("agent")
    }
    connection = function(key){
      ent:connections{key}
    }
    ui = function(){
      connections = ent:connections
        .values()
        .sort(function(a,b){
          a{"created"} cmp b{"created"}
        });
      {
        "name": wrangler:name(),
        "connections": connections.length() => connections | null,
        "invitation": invitation()
      }
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
// on ruleset_added
//
rule on_installation {
  select when wrangler ruleset_added where event:attr("rids") >< meta:rid
  pre {
    have_channel = agent_Rx()
  }
  if not have_channel then
    wrangler:createChannel(meta:picoId,"agent","sovrin") setting(channel)
  fired {
    ent:invitation_channel := channel
  } else {
    ent:invitation_channel := have_channel
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
      pc = {
        "label": im{"label"},
        "my_did": my_did,
        "@id": rm{"@id"}
      }.klog("pc")
    }
    fired {
      ent:pending_conn := ent:pending_conn.defaultsTo([]).append(pc);
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
      se = connection(their_key){"their_endpoint"}
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
      their_vk = publicKeys.head()
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
        "created": time:now(),
        "label": msg{"label"},
        "my_did": my_did,
        "their_did": connection{"DID"},
        "their_vk": their_vk,
        "their_endpoint": se
      }.klog("c")
    }
    fired {
      ent:connections{their_vk} := c;
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
      their_vk = service{"recipientKeys"}.head()
      cid = verified{["~thread","thid"]}
        .klog("cid")
      index = ent:pending_conn.defaultsTo([])
        .klog("pending connections")
        .reduce(function(a,p,i){
          a<0 && p{"@id"}==cid => i | a
        },-1)
        .klog("index")
      c = index < 0 => null | ent:pending_conn[index]
        .delete("@id")
        .put({
          "created": time:now(),
          "their_did": connection{"DID"},
          "their_vk": their_vk,
          "their_endpoint": service{"serviceEndpoint"}
        })
        .klog("c")
    }
    if typeof(index) == "Number" && index >= 0 then noop()
    fired {
      ent:connections{their_vk} := c;
      ent:pending_conn := ent:pending_conn.splice(index,1)
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
      se = connection(their_key){"their_endpoint"}
      may_respond = msg{"response_requested"} == false => false | true
    }
    if se && may_respond then http:post(se,body=pm) setting(http_response)
    fired {
/*
      ent:pingRes := ent:pingRes.defaultsTo(0) + 1;
      raise wrangler event "new_child_request" attributes {
        "name": "pingRes" + ent:pingRes, "rids": "org.sovrin.wire_message",
        "serviceEndpoint": se, "packedMessage": pm
      }
*/
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
      their_vk = event:attr("their_vk")
      rm = a_msg:trustPingMap()
      pm = indy:pack(
        rm.encode(),
        [their_vk],
        agent_Rx(){"id"}
      )
      se = connection(their_vk){"their_endpoint"}
    }
    if se then noop()
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
      se = connection(their_key){"their_endpoint"}
    }
    if se then
      http:post(se,body=pm) setting(http_response)
  }
//
// convenience rule to clean up known expired connection
//
  rule delete_connection {
    select when sovrin connection_expired
    pre {
      my_did = meta:eci
      their_vk = event:attr("their_vk")
      pairwise = ent:connections{their_vk}
    }
    if pairwise{"my_did"} == meta:eci then
      send_directive("delete",{"connection":pairwise})
    fired {
      ent:connections := ent:connections.delete(their_vk)
    }
  }
}

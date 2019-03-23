ruleset org.sovrin.agents {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.collection alias agents
      with Tx_role = "agent" Rx_role="agency"
    shares __testing, agents, agentByName
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      , { "name": "agents" }
      , { "name": "agentByName", "args": [ "name" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    agents = function(){
      agents:members()
    }
    agentByName = function(name){
      id = ent:agents{name};
      id => agents().filter(function(x){x{"Id"}==id})
                    .head()
                    .put("name",name)
          | null
    }
  }
  rule initialize_agency {
    select when wrangler ruleset_added where event:attr("rids") >< meta:rid
    pre {
      agency_eci = event:attr("rs_attrs"){"agency_eci"}
    }
    if ent:agency_eci.isnull() && ent:agents.isnull() then
    every {
      wrangler:createChannel(meta:picoId,"agents","sovrin") setting(channel);
      event:send({"eci":agency_eci, "domain":"agents", "type":"ready",
        "attrs": {"agents_eci":channel{"id"}}
      })
    }
    fired {
      ent:agency_eci := agency_eci;
      ent:agents := {};
      raise collection event "new_role_names" attributes {
        "Tx_role": "agent", "Rx_role": "agency"
      }
    }
  }
  rule map_id_to_name {
    select when collection new_member
    pre {
      name = event:attr("name")
      id = event:attr("Id")
    }
    fired {
      ent:agents{name} := id
    }
  }
}
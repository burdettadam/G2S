ruleset G2S.indy_sdk.ledger {
  meta {
    shares __testing, getNym,anchorSchema,blocks,getSchema,anchorCredDef,
      credDefs,createLinkedSecret,issuerCreateCredentialOffer,
      proverCreateCredentialReq,nym,createCred,storeCred,searchCredWithReq,searchCredWithReqForProof
    provides getNym,anchorSchema,blocks,getSchema,anchorCredDef,
      credDefs,createLinkedSecret,issuerCreateCredentialOffer,
      proverCreateCredentialReq,nym,createCred,storeCred,searchCredWithReq,searchCredWithReqForProof
  }
  global {
    __testing = { "queries":
      [ { "name": "getNym","args":["poolHandle","submitterDid","targetDid"] },
        { "name": "blocks","args":["pool_handle","submitter_did", "ledger_type"] }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
        { "domain": "ledger", "type": "nym", "attrs": [ "poolHandle", 
                                                        "signing_did",
                                                        "anchoring_did",
                                                        "anchoring_did_verkey",
                                                        "alias",
                                                        "role",
                                                        "walletHandle"] }
      ]
    }
    blocks = function(pool_handle,submitter_did, ledger_type){
      ledger:transactions(pool_handle,submitter_did, ledger_type)
    }
    getNym = function(poolHandle,submitterDid,targetDid){
      request = ledger:buildGetNymRequest(submitterDid,targetDid);
      ledger:submitRequest(poolHandle,request)
    }
    
    nym = defaction(pool_handle,signing_did,anchoring_did,anchoring_did_verkey,alias,role,wallet_handle){
      request = ledger:buildNymRequest(signing_did,
                               anchoring_did,
                               anchoring_did_verkey,
                               alias,
                               role).klog("nymrequest")
      response = ledger:signAndSubmitRequest(pool_handle,
                                    wallet_handle,
                                    signing_did,
                                    request).klog("ledger submit nym transaction")                         
      send_directive("nym transaction");
      returns response
    }
    
    anchorSchema = function(pool_handle,wallet_handle,submitter_did,issuerDid,name,version,attrNames){
      schema_id_schema = anoncred:issuerCreateSchema(issuerDid,name,version,attrNames).klog("issuercreateschema"); // returns [schema_id,schema]
      request = ledger:buildSchemaRequest(submitter_did,schema_id_schema[1]).klog("buildSchemaRequest");
      ledger:signAndSubmitRequest(pool_handle,wallet_handle,submitter_did,request).klog("singSubmit in anchorSchema")
    }
    
    getSchema = function(pool_handle,submitter_did,schema_id){
      request = ledger:buildGetSchemaRequest(submitter_did,schema_id);
      reponse = ledger:submitRequest(pool_handle,request);
      ledger:parseGetSchemaResponse(reponse)
    }
    /*getCredentialDefinition = function(submitter_did,data){
      request = ledger:buildCredDefRequest(submitter_did,data);
      response = ledger:submitRequest(request.decode()); // request needs to be a json object??...
      ledger:parseGetCredDefResponse(response)
    }*/
    anchorCredDef = defaction(pool_handle,wallet_handle, issuer_did,schema,tag, signature_type, cred_def_config){
      every{
      anoncred:issuerCreateAndStoreCredentialDef( wallet_handle, issuer_did, schema, tag, signature_type, cred_def_config ) setting(credDefId_credDef)
      }
      returns ledger:signAndSubmitRequest(pool_handle,wallet_handle,issuer_did,ledger:buildCredDefRequest(issuer_did,credDefId_credDef[1]))
    }
    credDefs = function(pool_handle,submitterDid, id){
      req = ledger:buildGetCredDefRequest(submitterDid, id );
      response = ledger:submitRequest(pool_handle,req);
      ledger:parseGetCredDefResponse(response)
    }
    issuerCreateCredentialOffer = function(wallet_handle,cred_def_id){
      anoncred:issuerCreateCredentialOffer(wallet_handle,cred_def_id)
    } 
    proverCreateCredentialReq = function(wallet_handle ,prover_did,cred_offer,cred_def,secret_id){
      anoncred:proverCreateCredentialReq(wallet_handle ,prover_did,cred_offer,cred_def,secret_id)
    }
    createLinkedSecret = defaction(wallet_handle, link_secret_id){
      anoncred:proverCreateMasterSecret(wallet_handle, link_secret_id) setting(id)
      returns id
    }
    createCred = function(wh, credOffer, credReq, credValues, revRegId, blobStorageReaderHandle){
      anoncred:issuerCreateCredential(wh, credOffer, credReq, credValues, revRegId, blobStorageReaderHandle)
    }
    storeCred = defaction(wh, credId, credReqMetadata, cred, credDef, revRegDef){
      anoncred:proverStoreCredential(wh, credId, credReqMetadata, cred, credDef, revRegDef)setting(results)
      returns results
    }
    searchCredWithReqForProof = function(poolHandle,wh, query, attr_count,pred_count, schemaSubmitterDid, schemaId , credDefSubmitterDid, credDefId ){
      identifiers_credsForProof = anoncred:proverSearchCredsForProof(wh, query, attr_count,pred_count);
      anoncred:proverGetEntitiesFromLedger(identifiers_credsForProof[0],poolHandle,schemaSubmitterDid,schemaId,credDefSubmitterDid,credDefId).append(identifiers_credsForProof[1]);
    }
    /*searchCredWithReq = function(wh,query){// TODO: support revocation and more querys 
      search_for_proof_request_handle = anoncred:proverSearchCredentials(wh,query,count);
      result = query{"requested_attributes"}.map(function(value,key){
        anoncred:proverFetchCredentialsForProofReq ( search_for_proof_request_handle, key , count )[0]{"cred_info"}});
      _result = result.put(query{"requested_predicates"}.map(function(value,key){
        anoncred:proverFetchCredentialsForProofReq ( search_for_proof_request_handle, key , count )[0]{"cred_info"}}));
      anoncred:proverCloseCredentialsSearchForProofReq ( search_for_proof_request_handle );                                                                    
      __result = _result.map(function(value,key){ {}.put(value{"referent"},value)  }).values().reduce(function(a,b){a.put(b)});
      //anoncrd:proverGetCredentials( wh, __result.klog("searchCredwithReq") )
      __result.klog("searchCredwithReq")
    }*/
    proverCreateProof = function(wh, proofReq, requestedCredentials, masterSecretName, schemas, credentialDefs, revStates){
      anoncred:proverCreateProof(wh, proofReq, requestedCredentials, masterSecretName, schemas, credentialDefs, revStates)
    }
  }
  rule nym {
    select when ledger nym
    nym(event:attr("poolHandle"),
        event:attr("signing_did"),
        event:attr("anchoring_did"),
        event:attr("anchoring_did_verkey"),
        event:attr("alias"),
        event:attr("role"),
        event:attr("walletHandle"))
  }
}

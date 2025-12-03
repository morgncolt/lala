package main

import (
  "fmt"
  "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

func (c *LandLedger) Vote(ctx contractapi.TransactionContextInterface, proposalID, choice string) error {
  inv, err := getInvokerID(ctx); if err != nil { return err }
  vkey := "vote:"+proposalID+":"+inv
  exists, _ := ctx.GetStub().GetState(vkey)
  if exists != nil { return fmt.Errorf("already voted") }
  return ctx.GetStub().PutState(vkey, []byte(choice))
}
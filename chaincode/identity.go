package main

import (
  "fmt"
  "github.com/hyperledger/fabric-contract-api-go/contractapi"
  cid "github.com/hyperledger/fabric-chaincode-go/pkg/cid"
)

func getInvokerID(ctx contractapi.TransactionContextInterface) (string, error) {
  id, err := cid.GetID(ctx.GetStub())
  if err != nil { return "", fmt.Errorf("get invoker ID: %w", err) }
  return id, nil
}

func hasRole(ctx contractapi.TransactionContextInterface, want string) (bool, error) {
  val, ok, err := cid.GetAttributeValue(ctx.GetStub(), "role")
  if err != nil { return false, err }
  if !ok { return false, nil }
  return val == want, nil
}
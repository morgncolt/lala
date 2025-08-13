package main

import (
"encoding/json"
"fmt"

"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type LandRecord struct {
ID          string `json:"id"`
Owner       string `json:"owner"`
GeoJSON     string `json:"geojson"`
Description string `json:"description"`
CreatedAt   string `json:"createdAt"`
}

type LandLedgerContract struct{ contractapi.Contract }

func (c *LandLedgerContract) Register(ctx contractapi.TransactionContextInterface, id, owner, geojson, description, createdAt string) error {
exists, err := c.Exists(ctx, id)
if err != nil {
return err
}
if exists {
return fmt.Errorf("record %s already exists", id)
}
rec := LandRecord{
ID: id, Owner: owner, GeoJSON: geojson, Description: description, CreatedAt: createdAt,
}
b, _ := json.Marshal(rec)
return ctx.GetStub().PutState(id, b)
}

func (c *LandLedgerContract) Get(ctx contractapi.TransactionContextInterface, id string) (*LandRecord, error) {
b, err := ctx.GetStub().GetState(id)
if err != nil {
return nil, err
}
if b == nil {
return nil, fmt.Errorf("record %s not found", id)
}
var rec LandRecord
if err := json.Unmarshal(b, &rec); err != nil {
return nil, err
}
return &rec, nil
}

func (c *LandLedgerContract) Exists(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
b, err := ctx.GetStub().GetState(id)
if err != nil {
return false, err
}
return b != nil, nil
}

func (c *LandLedgerContract) GetAll(ctx contractapi.TransactionContextInterface) ([]*LandRecord, error) {
results := []*LandRecord{}
iter, err := ctx.GetStub().GetStateByRange("", "")
if err != nil {
return nil, err
}
defer iter.Close()
for iter.HasNext() {
kv, err := iter.Next()
if err != nil {
return nil, err
}
var rec LandRecord
if err := json.Unmarshal(kv.Value, &rec); err != nil {
return nil, err
}
results = append(results, &rec)
}
return results, nil
}

func main() {
cc, err := contractapi.NewChaincode(new(LandLedgerContract))
if err != nil {
panic(err)
}
if err := cc.Start(); err != nil {
panic(err)
}
}

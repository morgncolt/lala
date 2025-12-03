type Parcel struct {
  ID     string `json:"id"`
  Data   string `json:"data"`
  Owner  string `json:"owner"`
}

func (c *LandLedger) CreateParcel(ctx contractapi.TransactionContextInterface, id, data string) error {
  inv, err := getInvokerID(ctx); if err != nil { return err }
  p := Parcel{ ID: id, Data: data, Owner: inv }
  b, _ := json.Marshal(p)
  return ctx.GetStub().PutState("parcel:"+id, b)
}

func (c *LandLedger) UpdateParcel(ctx contractapi.TransactionContextInterface, id, data string) error {
  inv, err := getInvokerID(ctx); if err != nil { return err }
  key := "parcel:"+id
  b, err := ctx.GetStub().GetState(key)
  if err != nil || b == nil { return fmt.Errorf("not found") }
  var p Parcel; _ = json.Unmarshal(b, &p)
  if p.Owner != inv { return fmt.Errorf("only owner can modify") }
  p.Data = data
  nb, _ := json.Marshal(p)
  return ctx.GetStub().PutState(key, nb)
}
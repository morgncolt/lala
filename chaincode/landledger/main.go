package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

func main() {
	cc, err := contractapi.NewChaincode(
		new(LandLedgerContract), // parcels
		new(ProjectContract),    // projects
	)
	if err != nil {
		panic(err)
	}
	cc.Info.Title = "LandLedgerChaincode"
	cc.Info.Version = "1.0.0"
	if err := cc.Start(); err != nil {
		panic(err)
	}
}

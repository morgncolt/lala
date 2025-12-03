package main

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type LandLedgerContract struct{ contractapi.Contract }

// internal helper
func getParcel(ctx contractapi.TransactionContextInterface, parcelID string) (*LandParcel, []byte, error) {
	b, err := ctx.GetStub().GetState(parcelID)
	if err != nil { return nil, nil, err }
	if b == nil { return nil, nil, fmt.Errorf("parcel %s not found", parcelID) }
	var p LandParcel
	if err := json.Unmarshal(b, &p); err != nil { return nil, nil, err }
	return &p, b, nil
}

func (c *LandLedgerContract) RegisterParcel(ctx contractapi.TransactionContextInterface, parcelJSON string) error {
	var p LandParcel
	if err := json.Unmarshal([]byte(parcelJSON), &p); err != nil {
		return fmt.Errorf("invalid parcel JSON: %w", err)
	}
	if p.ParcelID == "" || p.Owner == "" {
		return fmt.Errorf("parcelId and owner are required")
	}
	exists, err := c.Exists(ctx, p.ParcelID)
	if err != nil { return err }
	if exists { return fmt.Errorf("parcel %s already exists", p.ParcelID) }
	if p.CreatedAt == "" { p.CreatedAt = nowRFC3339() }

	payload, _ := json.Marshal(&p)
	if err := ctx.GetStub().PutState(p.ParcelID, payload); err != nil { return err }
	return addParcelIndexes(ctx, &p)
}

func (c *LandLedgerContract) GetParcel(ctx contractapi.TransactionContextInterface, parcelID string) (*LandParcel, error) {
	p, _, err := getParcel(ctx, parcelID)
	return p, err
}

func (c *LandLedgerContract) Exists(ctx contractapi.TransactionContextInterface, parcelID string) (bool, error) {
	b, err := ctx.GetStub().GetState(parcelID)
	if err != nil { return false, err }
	return b != nil, nil
}

func (c *LandLedgerContract) GetAllParcels(ctx contractapi.TransactionContextInterface) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil { return nil, err }
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		kv, err := iter.Next()
		if err != nil { return nil, err }
		var p LandParcel
		if err := json.Unmarshal(kv.Value, &p); err == nil && p.ParcelID != "" {
			out = append(out, &p)
		}
	}
	return out, nil
}

func (c *LandLedgerContract) QueryByOwner(ctx contractapi.TransactionContextInterface, owner string) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByPartialCompositeKey(ownerIndex, []string{owner})
	if err != nil { return nil, err }
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil { return nil, err }
		_, parts, err := ctx.GetStub().SplitCompositeKey(resp.Key)
		if err != nil || len(parts) != 2 { continue }
		if p, err := c.GetParcel(ctx, parts[1]); err == nil && p != nil {
			out = append(out, p)
		}
	}
	return out, nil
}

func (c *LandLedgerContract) QueryByTitle(ctx contractapi.TransactionContextInterface, titleNumber string) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByPartialCompositeKey(titleIndex, []string{titleNumber})
	if err != nil { return nil, err }
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil { return nil, err }
		_, parts, err := ctx.GetStub().SplitCompositeKey(resp.Key)
		if err != nil || len(parts) != 2 { continue }
		if p, err := c.GetParcel(ctx, parts[1]); err == nil && p != nil {
			out = append(out, p)
		}
	}
	return out, nil
}

func (c *LandLedgerContract) UpdateDescription(ctx contractapi.TransactionContextInterface, parcelID, newDesc string) error {
	p, _, err := getParcel(ctx, parcelID)
	if err != nil { return err }
	p.Description = newDesc
	payload, _ := json.Marshal(p)
	return ctx.GetStub().PutState(parcelID, payload)
}

func (c *LandLedgerContract) UpdateGeometry(ctx contractapi.TransactionContextInterface, parcelID, coordsJSON, areaSqKm string) error {
	p, _, err := getParcel(ctx, parcelID)
	if err != nil { return err }

	var coords []Coordinate
	if err := json.Unmarshal([]byte(coordsJSON), &coords); err != nil {
		return fmt.Errorf("invalid coordinates JSON: %w", err)
	}
	area, err := strconv.ParseFloat(areaSqKm, 64)
	if err != nil { return fmt.Errorf("invalid area: %w", err) }

	p.Coordinates = coords
	p.AreaSqKm = area

	payload, _ := json.Marshal(p)
	return ctx.GetStub().PutState(parcelID, payload)
}

func (c *LandLedgerContract) TransferOwner(ctx contractapi.TransactionContextInterface, parcelID, newOwner string) error {
	if newOwner == "" { return fmt.Errorf("new owner required") }
	p, _, err := getParcel(ctx, parcelID)
	if err != nil { return err }

	if err := removeParcelIndexes(ctx, p); err != nil { return err }
	p.Owner = newOwner
	if err := addParcelIndexes(ctx, p); err != nil { return err }

	payload, _ := json.Marshal(p)
	return ctx.GetStub().PutState(parcelID, payload)
}

func (c *LandLedgerContract) GetHistory(ctx contractapi.TransactionContextInterface, parcelID string) ([]*HistoryEntry, error) {
	iter, err := ctx.GetStub().GetHistoryForKey(parcelID)
	if err != nil { return nil, err }
	defer iter.Close()

	var out []*HistoryEntry
	for iter.HasNext() {
		r, err := iter.Next()
		if err != nil { return nil, err }
		var val *LandParcel
		if !r.IsDelete && len(r.Value) > 0 {
			var tmp LandParcel
			if err := json.Unmarshal(r.Value, &tmp); err == nil { val = &tmp }
		}
		out = append(out, &HistoryEntry{TxID: r.TxId, IsDelete: r.IsDelete, Value: val})
	}
	return out, nil
}

func (c *LandLedgerContract) DeleteParcel(ctx contractapi.TransactionContextInterface, parcelID string) error {
	p, _, err := getParcel(ctx, parcelID)
	if err != nil { return err }
	if err := ctx.GetStub().DelState(parcelID); err != nil { return err }
	return removeParcelIndexes(ctx, p)
}

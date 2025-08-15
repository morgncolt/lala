package main

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type Coordinate struct {
    Lat float64 `json:"lat"`
    Lng float64 `json:"lng"`
}

type LandParcel struct {
    ParcelID    string       `json:"parcelId"`           // primary key
    TitleNumber string       `json:"titleNumber"`        // may equal ParcelID in UI
    Owner       string       `json:"owner"`
    Coordinates []Coordinate `json:"coordinates"`
    AreaSqKm    float64      `json:"areaSqKm"`
    Description string       `json:"description"`
    CreatedAt   string       `json:"createdAt"`          // ISO8601 if provided by client
    Verified    bool         `json:"verified"`
}


// History entry (for per-parcel audit)
type HistoryEntry struct {
	TxID     string      `json:"txId"`
	IsDelete bool        `json:"isDelete"`
	Value    *LandParcel `json:"value"`
}

// Composite key namespaces
const (
	ownerIndex = "owner~id"
	titleIndex = "title~id"
)

// ==== Contract ====

type LandLedgerContract struct{ contractapi.Contract }

// RegisterParcel stores a new parcel. Arg0 must be a JSON string matching LandParcel.
// Required fields: parcelId, owner. If titleNumber is empty, it will mirror parcelId.
func (c *LandLedgerContract) RegisterParcel(ctx contractapi.TransactionContextInterface, parcelJSON string) error {
	var p LandParcel
	if err := json.Unmarshal([]byte(parcelJSON), &p); err != nil {
		return fmt.Errorf("invalid parcel JSON: %w", err)
	}
	if p.ParcelID == "" || p.Owner == "" {
		return fmt.Errorf("parcelId and owner are required")
	}
	exists, err := c.Exists(ctx, p.ParcelID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("parcel %s already exists", p.ParcelID)
	}
	if p.TitleNumber == "" {
		p.TitleNumber = p.ParcelID
	}
	// Persist
	b, _ := json.Marshal(p)
	if err := ctx.GetStub().PutState(p.ParcelID, b); err != nil {
		return err
	}
	// Secondary indexes
	if err := c.addIndexes(ctx, &p); err != nil {
		return err
	}
	return nil
}

// GetParcel returns a single parcel by id.
func (c *LandLedgerContract) GetParcel(ctx contractapi.TransactionContextInterface, parcelID string) (*LandParcel, error) {
	b, err := ctx.GetStub().GetState(parcelID)
	if err != nil {
		return nil, err
	}
	if b == nil {
		return nil, fmt.Errorf("parcel %s not found", parcelID)
	}
	var p LandParcel
	if err := json.Unmarshal(b, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

// GetAllParcels returns all parcels.
func (c *LandLedgerContract) GetAllParcels(ctx contractapi.TransactionContextInterface) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		kv, err := iter.Next()
		if err != nil {
			return nil, err
		}
		var p LandParcel
		if err := json.Unmarshal(kv.Value, &p); err != nil {
			return nil, err
		}
		out = append(out, &p)
	}
	return out, nil
}

// QueryByOwner returns all parcels for a given owner (wallet/email/etc.).
func (c *LandLedgerContract) QueryByOwner(ctx contractapi.TransactionContextInterface, owner string) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByPartialCompositeKey(ownerIndex, []string{owner})
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil {
			return nil, err
		}
		_, parts, err := ctx.GetStub().SplitCompositeKey(resp.Key)
		if err != nil || len(parts) != 2 {
			continue
		}
		id := parts[1]
		p, err := c.GetParcel(ctx, id)
		if err == nil && p != nil {
			out = append(out, p)
		}
	}
	return out, nil
}

// QueryByTitle returns a parcel(s) with a specific title number.
func (c *LandLedgerContract) QueryByTitle(ctx contractapi.TransactionContextInterface, titleNumber string) ([]*LandParcel, error) {
	iter, err := ctx.GetStub().GetStateByPartialCompositeKey(titleIndex, []string{titleNumber})
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*LandParcel
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil {
			return nil, err
		}
		_, parts, err := ctx.GetStub().SplitCompositeKey(resp.Key)
		if err != nil || len(parts) != 2 {
			continue
		}
		id := parts[1]
		p, err := c.GetParcel(ctx, id)
		if err == nil && p != nil {
			out = append(out, p)
		}
	}
	return out, nil
}

// TransferOwner updates the owner and reindexes.
func (c *LandLedgerContract) TransferOwner(ctx contractapi.TransactionContextInterface, parcelID, newOwner string) error {
	if newOwner == "" {
		return fmt.Errorf("newOwner required")
	}
	p, err := c.GetParcel(ctx, parcelID)
	if err != nil {
		return err
	}
	// remove old index
	if err := c.removeIndexes(ctx, p); err != nil {
		return err
	}
	p.Owner = newOwner
	// save
	b, _ := json.Marshal(p)
	if err := ctx.GetStub().PutState(parcelID, b); err != nil {
		return err
	}
	// add new indexes
	return c.addIndexes(ctx, p)
}

// UpdateDescription updates the parcel description.
func (c *LandLedgerContract) UpdateDescription(ctx contractapi.TransactionContextInterface, parcelID, desc string) error {
	p, err := c.GetParcel(ctx, parcelID)
	if err != nil {
		return err
	}
	p.Description = desc
	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(parcelID, b)
}

// UpdateGeometry replaces coordinates and/or area; coordsJSON must be JSON array of {lat,lng}.
func (c *LandLedgerContract) UpdateGeometry(ctx contractapi.TransactionContextInterface, parcelID, coordsJSON, areaSqKm string) error {
	p, err := c.GetParcel(ctx, parcelID)
	if err != nil {
		return err
	}
	if coordsJSON != "" {
		var coords []Coordinate
		if err := json.Unmarshal([]byte(coordsJSON), &coords); err != nil {
			return fmt.Errorf("invalid coordinates JSON: %w", err)
		}
		p.Coordinates = coords
	}
	if areaSqKm != "" {
		if v, err := strconv.ParseFloat(areaSqKm, 64); err == nil {
			p.AreaSqKm = v
		}
	}
	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(parcelID, b)
}

// DeleteParcel removes the parcel and secondary indexes.
func (c *LandLedgerContract) DeleteParcel(ctx contractapi.TransactionContextInterface, parcelID string) error {
	p, err := c.GetParcel(ctx, parcelID)
	if err != nil {
		return err
	}
	if err := ctx.GetStub().DelState(parcelID); err != nil {
		return err
	}
	return c.removeIndexes(ctx, p)
}

// Exists returns true if a parcel exists.
func (c *LandLedgerContract) Exists(ctx contractapi.TransactionContextInterface, parcelID string) (bool, error) {
	b, err := ctx.GetStub().GetState(parcelID)
	if err != nil {
		return false, err
	}
	return b != nil, nil
}

// GetHistory returns the history for a parcel (txId + value snapshots).
func (c *LandLedgerContract) GetHistory(ctx contractapi.TransactionContextInterface, parcelID string) ([]*HistoryEntry, error) {
	iter, err := ctx.GetStub().GetHistoryForKey(parcelID)
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*HistoryEntry
	for iter.HasNext() {
		r, err := iter.Next()
		if err != nil {
			return nil, err
		}
		var val *LandParcel
		if !r.IsDelete && len(r.Value) > 0 {
			var p LandParcel
			if err := json.Unmarshal(r.Value, &p); err == nil {
				val = &p
			}
		}
		out = append(out, &HistoryEntry{
			TxID:     r.TxId,
			IsDelete: r.IsDelete,
			Value:    val,
		})
	}
	return out, nil
}

// ==== private helpers ====

func (c *LandLedgerContract) addIndexes(ctx contractapi.TransactionContextInterface, p *LandParcel) error {
	if p == nil {
		return nil
	}
	// owner~id
	if p.Owner != "" {
		key, err := ctx.GetStub().CreateCompositeKey(ownerIndex, []string{p.Owner, p.ParcelID})
		if err != nil {
			return err
		}
		if err := ctx.GetStub().PutState(key, []byte{0}); err != nil {
			return err
		}
	}
	// title~id
	if p.TitleNumber != "" {
		key, err := ctx.GetStub().CreateCompositeKey(titleIndex, []string{p.TitleNumber, p.ParcelID})
		if err != nil {
			return err
		}
		if err := ctx.GetStub().PutState(key, []byte{0}); err != nil {
			return err
		}
	}
	return nil
}

func (c *LandLedgerContract) removeIndexes(ctx contractapi.TransactionContextInterface, p *LandParcel) error {
	if p == nil {
		return nil
	}
	if p.Owner != "" {
		key, err := ctx.GetStub().CreateCompositeKey(ownerIndex, []string{p.Owner, p.ParcelID})
		if err == nil {
			_ = ctx.GetStub().DelState(key)
		}
	}
	if p.TitleNumber != "" {
		key, err := ctx.GetStub().CreateCompositeKey(titleIndex, []string{p.TitleNumber, p.ParcelID})
		if err == nil {
			_ = ctx.GetStub().DelState(key)
		}
	}
	return nil
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

package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// SmartContract provides functions for managing land parcels
type SmartContract struct {
	contractapi.Contract
}

// LandParcel describes a registered parcel
type LandParcel struct {
	ParcelID     string       `json:"parcelId"`
	TitleNumber  string       `json:"title_number"`
	Owner        string       `json:"owner"`
	Coordinates  []Coordinate `json:"coordinates"`
	AreaSqKm     float64      `json:"area_sqkm"`
	Description  string       `json:"description"`
	Verified     bool         `json:"verified"`
	CreatedAt    string       `json:"createdAt"`
}

// Coordinate represents a geographic point
type Coordinate struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// parcelKey builds a world state key
func parcelKey(id string) string {
    return "parcel_" + id
}

// =====================  Ledger Bootstrapping =====================

// InitLedger adds a sample parcel for testing
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	sample := LandParcel{
		ParcelID:    "P001",
		TitleNumber: "TN-001",
		Owner:       "Gov",
		Coordinates: []Coordinate{{Lat: 37.4219, Lng: -122.0841}},
		AreaSqKm:    1.23,
		Description: "Sample demo parcel",
		Verified:    true,
		CreatedAt:   time.Now().Format(time.RFC3339),
	}

	bytes, err := json.Marshal(sample)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(parcelKey(sample.ParcelID), bytes)
}

// =====================  Create & Read =====================

// CreateParcel adds a new land parcel
func (s *SmartContract) CreateLandRecord(ctx contractapi.TransactionContextInterface, parcelID string, titleNumber string, owner string, coordinatesJSON string, areaSqKm float64, description string) error {
	exists, err := s.ParcelExists(ctx, parcelID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("parcel %s already exists", parcelID)
	}

	var coords []Coordinate
	if err := json.Unmarshal([]byte(coordinatesJSON), &coords); err != nil {
		return fmt.Errorf("invalid coordinates JSON: %v", err)
	}

	parcel := LandParcel{
		ParcelID:    parcelID,
		TitleNumber: titleNumber,
		Owner:       owner,
		Coordinates: coords,
		AreaSqKm:    areaSqKm,
		Description: description,
		Verified:    false,
		CreatedAt:   time.Now().Format(time.RFC3339),
	}

	bytes, err := json.Marshal(parcel)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(parcelKey(parcelID), bytes)
}

// DebugGetRawState returns raw bytes of a given key
func (s *SmartContract) DebugGetRawState(ctx contractapi.TransactionContextInterface, key string) (string, error) {
    bytes, err := ctx.GetStub().GetState(key)
    if err != nil {
        return "", fmt.Errorf("failed to read key %s: %v", key, err)
    }
    if bytes == nil {
        return "", fmt.Errorf("key %s does not exist", key)
    }
    return string(bytes), nil
}


// ReadParcel returns parcel data by ID
func (s *SmartContract) ReadParcel(ctx contractapi.TransactionContextInterface, parcelID string) (*LandParcel, error) {
    // Construct the key consistently
    key := parcelKey(parcelID)

    // Get state from ledger
    bytes, err := ctx.GetStub().GetState(key)
    if err != nil {
        return nil, fmt.Errorf("failed to read parcel %s: %v", parcelID, err)
    }
    if bytes == nil {
        return nil, fmt.Errorf("parcel %s does not exist", parcelID)
    }

    // Unmarshal the parcel JSON
    var parcel LandParcel
    if err := json.Unmarshal(bytes, &parcel); err != nil {
        return nil, fmt.Errorf("failed to unmarshal parcel: %v", err)
    }

    return &parcel, nil
}


// =====================  Updates =====================

// TransferOwnership changes the parcel owner
func (s *SmartContract) TransferOwnership(ctx contractapi.TransactionContextInterface, parcelID string, newOwner string) error {
	parcel, err := s.ReadParcel(ctx, parcelID)
	if err != nil {
		return err
	}

	parcel.Owner = newOwner

	bytes, err := json.Marshal(parcel)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(parcelKey(parcelID), bytes)
}

// VerifyParcel updates verification status
func (s *SmartContract) VerifyParcel(ctx contractapi.TransactionContextInterface, parcelID string, verified bool) error {
	parcel, err := s.ReadParcel(ctx, parcelID)
	if err != nil {
		return err
	}

	parcel.Verified = verified

	bytes, err := json.Marshal(parcel)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(parcelKey(parcelID), bytes)
}

// =====================  Queries =====================

func (s *SmartContract) GetAllParcels(ctx contractapi.TransactionContextInterface) ([]*LandParcel, error) {
    resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
    if err != nil {
        return nil, err
    }
    defer resultsIterator.Close()

    var parcels []*LandParcel
    for resultsIterator.HasNext() {
        queryResponse, err := resultsIterator.Next()
        if err != nil {
            return nil, err
        }

        // Only include records with "parcel_" prefix
        if !strings.HasPrefix(queryResponse.Key, "parcel_") {
            continue
        }

        var parcel LandParcel
        err = json.Unmarshal(queryResponse.Value, &parcel)
        if err != nil {
            continue // skip malformed
        }
        parcels = append(parcels, &parcel)
    }

    return parcels, nil
}



// ParcelExists checks if a parcel exists
func (s *SmartContract) ParcelExists(ctx contractapi.TransactionContextInterface, parcelID string) (bool, error) {
	bytes, err := ctx.GetStub().GetState(parcelKey(parcelID))
	if err != nil {
		return false, err
	}
	return bytes != nil, nil
}

// =====================  main() =====================

func main() {

	cc, err := contractapi.NewChaincode(new(SmartContract))
	if err != nil {
		panic(fmt.Sprintf("Failed to create chaincode: %v", err))
	}
	if err := cc.Start(); err != nil {
		panic(fmt.Sprintf("Failed to start chaincode: %v", err))
	}
}

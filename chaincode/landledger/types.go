package main

type Coordinate struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type LandParcel struct {
	ParcelID    string       `json:"parcelId"`
	TitleNumber string       `json:"titleNumber"`
	Owner       string       `json:"owner"`
	Coordinates []Coordinate `json:"coordinates"`
	AreaSqKm    float64      `json:"areaSqKm"`
	Description string       `json:"description"`
	CreatedAt   string       `json:"createdAt"`
	Verified    bool         `json:"verified"`
}

type HistoryEntry struct {
	TxID     string      `json:"txId"`
	IsDelete bool        `json:"isDelete"`
	Value    *LandParcel `json:"value"`
}

type Milestone struct {
	Label    string `json:"label"`
	Amount   int64  `json:"amount"`
	Released bool   `json:"released"`
}

type Project struct {
	ProjectID     string        `json:"projectId"`
	ParcelID      string        `json:"parcelId"`
	Owner         string        `json:"owner"`
	// Use string here to avoid undefined type issues if enums file isn't compiled.
	Type          string        `json:"type"`
	Goal          int64         `json:"goal"`
	RequiredVotes int           `json:"requiredVotes"`
	AmountPerVote int64         `json:"amountPerVote"`
	Funded        int64         `json:"funded"`
	Status        ProjectStatus `json:"status"`
	Voters        []string      `json:"voters"`
	Milestones    []Milestone   `json:"milestones"`
	Contractor    string        `json:"contractor"`
	TitleNumber   string        `json:"titleNumber"`
	Description   string        `json:"description"`
	CreatedAt     string        `json:"createdAt"`
	UpdatedAt     string        `json:"updatedAt"`
}

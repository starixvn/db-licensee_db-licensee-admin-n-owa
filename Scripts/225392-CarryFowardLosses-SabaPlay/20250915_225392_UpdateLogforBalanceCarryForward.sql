/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20250915@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Update log for Balance Carry Forward setting [RedmineID: #225392]
*/
USE bodb_CustomerLog
GO

UPDATE LA_LogAction 
SET 
Items = 
'{
  "Items": [
    {"Alias": "pi","Item": "Payer Information"},
    {"Alias": "pn","Item": "Payer Name"},
    {"Alias": "bn","Item": "Payer Brand Name"},
    {"Alias": "iv","Item": "Invoice Language"},
    {"Alias": "ld","Item": "Launch Date"},
    {"Alias": "sd","Item": "Suspended Date"},
    {"Alias": "tmd","Item": "Terminated Date"},
    {"Alias": "pp","Item": "Payer Platform"},
    {"Alias": "bg","Item": "Billing Group"},
    {"Alias": "dc","Item": "Description"},
    {"Alias": "a1","Item": "Address 1"},
    {"Alias": "cn1","Item": "Payer Company Name"},
    {"Alias": "ad1","Item": "Address"},
    {"Alias": "an1","Item": "Attn Name"},
    {"Alias": "a2","Item": "Address 2"},
    {"Alias": "cn2","Item": "Payer Company Name"},
    {"Alias": "ad2","Item": "Address"},
    {"Alias": "an2","Item": "Attn Name"},
    {"Alias": "bcs","Item": "Base Currency Setting"},
    {"Alias": "c","Item": "Currency"},
    {"Alias": "lc","Item": "Licensee Code"},
    {"Alias": "fd","Item": "From Date"},
    {"Alias": "td","Item": "To Date"},
    {"Alias": "bcfs","Item": "Balance Carry Forward Setting"},
    {"Alias": "ibcf","Item": "Description"},
    {"Alias": "bfd","Item": "From Date"},
    {"Alias": "btd","Item": "To Date"}
  ]
}'
WHERE actionID IN (1000, 1001)
GO







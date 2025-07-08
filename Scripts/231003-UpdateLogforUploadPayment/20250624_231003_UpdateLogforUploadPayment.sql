/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20250624@Eddie
	DB: DBLOG.bodb_CustomerLog
	Task: Update log for "Upload payment" [RedmineID: #231003]
*/
USE bodb_CustomerLog
GO

UPDATE LA_LogAction 
SET 
Items = 
'{"Items": [
{"Alias": "gi", "Item": "General Info"},
{"Alias": "p", "Item": "Payer"},
{"Alias": "r", "Item": "RefNo"},
{"Alias": "pi", "Item": "Payment Info"},
{"Alias": "pn", "Item": "Payment No"},
{"Alias": "rd", "Item": "Received Date (mm/dd/yyyy)"},
{"Alias": "b", "Item": "Biller"},
{"Alias": "fc", "Item": "From Customer"},
{"Alias": "tc", "Item": "To Customer"},
{"Alias": "a", "Item":  "Amount"},
{"Alias": "fa", "Item": "From Amount"},
{"Alias": "ta", "Item": "To Amount"},
{"Alias": "ar", "Item": "Actual Rate"},
{"Alias": "rp", "Item": "Rebate Payment (Y/N)"},
{"Alias": "bu", "Item": "Business Unit"},
{"Alias": "d" ,"Item": "Description"}]}
'
WHERE ActionNameEN = 'Upload payment'
GO
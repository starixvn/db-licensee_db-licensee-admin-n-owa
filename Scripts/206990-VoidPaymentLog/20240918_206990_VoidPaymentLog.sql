/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20240918@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Add new log setting RedmineId #206990
*/
USE [bodb_CustomerLog]
GO

INSERT INTO LA_LogAction (ActionID,	ActionTypeID,	SPName,	ActionNameEN,	Items) VALUES
(
2102, 21, NULL, 'Void payment', 
'{"Items": [
{"Alias": "gi", "Item": "General Info"},
{"Alias": "p", "Item": "Payer"},
{"Alias": "r", "Item": "Ref No."},
{"Alias": "pi", "Item": "Payment Info"},
{"Alias": "pn", "Item": "Payment No."},
{"Alias": "b", "Item": "Biller"},
{"Alias": "pt", "Item": "Payment Type"},
{"Alias": "a", "Item":  "Payment Amount"},
{"Alias": "ra", "Item":  "Remaining Amount"},
{"Alias": "rd", "Item": "Received Date"},
{"Alias": "ud", "Item": "Uploaded Date"},
{"Alias": "mb", "Item": "Modified By"},
{"Alias": "md" ,"Item": "Modified Date"}]}'
)



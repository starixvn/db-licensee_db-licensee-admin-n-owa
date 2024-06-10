/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20231026@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for Upload payment RedmineId #193656
*/
USE [bodb_CustomerLog]
GO

INSERT INTO [dbo].[LA_LogActionType](ActionTypeID, ActionTypeNameEN)
 VALUES (22, 'Payment Allocation')


INSERT INTO LA_LogAction (ActionID, ActionTypeID, ActionNameEN, Items)
VALUES (2201, 22, 'Allocate Document', '')

UPDATE LA_LogAction 
SET 
Items = 
'{"Items": [
{"Alias": "gi", "Item": "General Info"},
{"Alias": "p", "Item": "Payer"},
{"Alias": "lc", "Item": "Licensee Code"},
{"Alias": "is", "Item": "Invoice Settlement"},
{"Alias": "d", "Item": "Date"},
{"Alias": "dn", "Item": "Document No"},
{"Alias": "dt", "Item": "Document Type"},
{"Alias": "ia", "Item": "Invoice Amount"},
{"Alias": "pa", "Item":  "Payment Amount"},
{"Alias": "am", "Item": "Applied Amount"},
{"Alias": "rs", "Item": "Rebate Settlement"},
{"Alias": "d1", "Item": "Date"},
{"Alias": "dn1", "Item": "Document No"},
{"Alias": "dt1", "Item": "Document Type"},
{"Alias": "ia1", "Item": "Invoice Amount"},
{"Alias": "pa1", "Item":  "Payment Amount"},
{"Alias": "am1", "Item": "Applied Amount"}]}
'
WHERE ACtionID = 2201



select * from LA_LogAction





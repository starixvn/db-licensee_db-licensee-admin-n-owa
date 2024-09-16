/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/

/*
	Created: 20240814@Danny
	DB: DBLOG.bodb_CustomerLog
	Description: Alter table add more cols
*/

UPDATE LA_LogAction WITH(ROWLOCK)
SET Items =
'{"Items": [{"Alias":"bi","Item":"Biller Information"}, 
{"Alias":"bn","Item":"Biller Name"},
{"Alias":"bfn","Item":"Biller Full Name"},
{"Alias":"bna","Item":"Biller Name Abbreviation"}, 
{"Alias":"cn","Item":"Biller Company Name"}, 
{"Alias":"a1","Item":"Address 1"}, 
{"Alias":"a2","Item":"Address 2"}, 
{"Alias":"ia","Item":"Is Active"}, 
{"Alias":"b1","Item":"Bank 1"}, 
{"Alias":"bnn1","Item":"Beneficiary Name"}, 
{"Alias":"an1","Item":"Account Number"}, 
{"Alias":"ban1","Item":"Bank Name"}, 
{"Alias":"ba1","Item":"Bank Address"},
{"Alias":"ib1","Item":"IBAN"},
{"Alias":"sc1","Item":"Swift Code"},
{"Alias":"cb1","Item":"Correspondent Bank"},
{"Alias":"can1","Item":"Correspondent Account Number"},
{"Alias":"ca1","Item":"Correspondent Account Address"},
{"Alias":"cs1","Item":"Correspondent Swift Code"},
{"Alias":"b2","Item":"Bank 2"}, 
{"Alias":"bnn2","Item":"Beneficiary Name"}, 
{"Alias":"an2","Item":"Account Number"}, 
{"Alias":"ban2","Item":"Bank Name"}, 
{"Alias":"ba2","Item":"Bank Address"},
{"Alias":"ib2","Item":"IBAN"},
{"Alias":"sc2","Item":"Swift Code"},
{"Alias":"cb2","Item":"Correspondent Bank"},
{"Alias":"can2","Item":"Correspondent Account Number"},
{"Alias":"ca2","Item":"Correspondent Account Address"},
{"Alias":"cs2","Item":"Correspondent Swift Code"},
{"Alias":"b3","Item":"Bank 3"}, 
{"Alias":"bnn3","Item":"Beneficiary Name"}, 
{"Alias":"an3","Item":"Account Number"}, 
{"Alias":"ban3","Item":"Bank Name"}, 
{"Alias":"ba3","Item":"Bank Address"},
{"Alias":"ib3","Item":"IBAN"},
{"Alias":"sc3","Item":"Swift Code"},
{"Alias":"cb3","Item":"Correspondent Bank"},
{"Alias":"can3","Item":"Correspondent Account Number"},
{"Alias":"ca3","Item":"Correspondent Account Address"},
{"Alias":"cs3","Item":"Correspondent Swift Code"}
]}'
WHERE ActionTypeID = 11



UPDATE   LA_LogAction   WITH(ROWLOCK)
SET Items = 
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
{"Alias": "d" ,"Item": "Description"}]}'

WHERE ActionTypeID = 21
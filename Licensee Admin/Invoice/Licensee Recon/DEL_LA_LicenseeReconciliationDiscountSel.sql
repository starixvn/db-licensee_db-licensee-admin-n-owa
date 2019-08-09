/*<info serverAlias="DBCUST-bodb_licensee" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE[dbo].LA_LicenseeReconciliationDiscountSel
/*  
	Created: 20190725@Bruce
	Task : The list of licensee who takes Sportsbook PT 91% on NAP; and on LA: 12% licensing fee, 3% discount
	DB: DBCUST.bodb_licensee
	
	Revisions:
		- 20190725@Bruce: create SP

*/
AS
BEGIN
	SELECT LicenseeId, LicenseeName,PartyId,LicenseeCode
	FROM (VALUES
		 (2,'asiabet88', 15,'PHL-LSEE-F88 EUR')
		,(6,'TLC',19,'PHL-LSEE-TLC EUR')
		,(12,'HAIFA',24,'PHL-LSEE-BBIN CNY')
		,(122,'IBO',82,'PHL-LSEE-iBO EUR')
		,(225,'BBIN2',296,'PHL-LSEE-BBIN2 CNY')
		,(238,'zt828',289,'PHL-LSEE-ZT828 EUR')
		,(273,'A1game',368,'PHL-LSEE-A1GAME EUR')
		,(279,'Bobbet',346,'PHL-LSEE-BOBBET EUR')
		,(288,'ig128',366,'PHL-LSEE-IG128 EUR')
		,(315,'txwl002',373,'PHL-LSEE-TXWL002 EUR')
		,(316,'sbt88',375,'PHL-LSEE-SBT88 EUR')	
	) x(LicenseeId, LicenseeName,PartyId,LicenseeCode)

END

/*
[
	{
		"LicenseeId": "2",
		"LicenseeName": "asiabet88",
		"PartyId": "15",
		"LicenseeCode": "PHL-LSEE-F88 EUR"
	},
	{
		"LicenseeId": "6",
		"LicenseeName": "TLC",
		"PartyId": "19",
		"LicenseeCode": "PHL-LSEE-TLC EUR"
	},
	{
		"LicenseeId": "12",
		"LicenseeName": "HAIFA",
		"PartyId": "24",
		"LicenseeCode": "PHL-LSEE-BBIN CNY"
	},
	{
		"LicenseeId": "122",
		"LicenseeName": "IBO",
		"PartyId": "82",
		"LicenseeCode": "PHL-LSEE-iBO EUR"
	},
	{
		"LicenseeId": "225",
		"LicenseeName": "BBIN2",
		"PartyId": "296",
		"LicenseeCode": "PHL-LSEE-BBIN2 CNY"
	},
	{
		"LicenseeId": "238",
		"LicenseeName": "zt828",
		"PartyId": "289",
		"LicenseeCode": "PHL-LSEE-ZT828 EUR"
	},
	{
		"LicenseeId": "273",
		"LicenseeName": "A1game",
		"PartyId": "368",
		"LicenseeCode": "PHL-LSEE-A1GAME EUR"
	},
	{
		"LicenseeId": "279",
		"LicenseeName": "Bobbet",
		"PartyId": "346",
		"LicenseeCode": "PHL-LSEE-BOBBET EUR"
	},
	{
		"LicenseeId": "288",
		"LicenseeName": "ig128",
		"PartyId": "366",
		"LicenseeCode": "PHL-LSEE-IG128 EUR"
	},
	{
		"LicenseeId": "315",
		"LicenseeName": "txwl002",
		"PartyId": "373",
		"LicenseeCode": "PHL-LSEE-TXWL002 EUR"
	},
	{
		"LicenseeId": "316",
		"LicenseeName": "sbt88",
		"PartyId": "375",
		"LicenseeCode": "PHL-LSEE-SBT88 EUR"
	}
]
*/
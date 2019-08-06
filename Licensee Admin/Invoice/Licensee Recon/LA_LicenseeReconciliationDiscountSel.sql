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
	SELECT LicenseeId, LicenseeName,PartyId
	FROM (VALUES
	 (2,'asiabet88', 15)
	,(6,'TLC',19)
	,(12,'HAIFA',24)
	,(122,'IBO',82)
	,(225,'BBIN2',296)
	,(238,'zt828',289)
	,(273,'A1game',368)
	,(279,'Bobbet',346)
	,(288,'ig128',366)
	,(315,'txwl002',373)
	,(316,'sbt88',375)) x(LicenseeId, LicenseeName,PartyId)

END
/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

CREATE FUNCTION [dbo].LA_f_LicenseeReconciliationDiscountSel()
/*  
	Created: 20190725@Bruce
	Task : The list of licensee who takes Sportsbook PT 91% on NAP; and on LA: 12% licensing fee, 3% discount
	DB: DBLIC.bodb_licensee
	
	Revisions:
		- 20190725@Bruce: create function

*/
RETURNS @tblResult TABLE(LicenseeName VARCHAR(50),LicenseeId INT)
AS
BEGIN
	INSERT INTO @tblResult(LicenseeId, LicenseeName) VALUES
	 (2,'asiabet88')
	,(6,'TLC')
	,(12,'HAIFA')
	,(122,'IBO')
	,(225,'BBIN2')
	,(238,'zt828')
	,(273,'A1game')
	,(279,'Bobbet')
	,(288,'ig128')
	,(315,'txwl002')
	,(316,'sbt88')

	RETURN
END
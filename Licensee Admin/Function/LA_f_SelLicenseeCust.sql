/*<info serverAlias="DBCUST-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_SelLicenseeCust](@LicenseeID INT = 0)

RETURNS @tbLicenseeCust TABLE 
(
	[LicenseeID] [int],
	[CustID] [int],
	[RoleID] [tinyint],
	[Currency] [int],
	[CurrencyName] [varchar](20),
	[Description] [varchar](100)
)
AS
/*
	Created: 20190510@Percy
	Task: Get LicenseesCust list
	DB: DBCUST.bodb_Licensee
	Remark: Clone from Function: f_SelLicenseeCust (DBLIC.bodb_Licensee)

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]

	Param's Explanation:
*/
BEGIN
	-- Get normal LicenseeCust list
	INSERT INTO @tbLicenseeCust (LicenseeID, CustID, RoleID, Currency, CurrencyName, [Description])
	SELECT LicenseeID, CustID, RoleID, Currency, CurrencyName, [Description]
	FROM LicenseeCust
	WHERE ISNULL(@LicenseeID, 0) = 0 OR LicenseeID = @LicenseeID
	
	-- Hardcode for KeenOcean licensee
	DECLARE @KeenOceanID INT
	DECLARE @RMB INT
	DECLARE @YUN INT

	SELECT @KeenOceanID = LicenseeID FROM dbo.Licensees WITH (NOLOCK) WHERE LicenseeName LIKE 'KeenOcean'
	SELECT @RMB = ExchangeID FROM CustDB.dbo.Exchange WITH (NOLOCK) WHERE currency = 'RMB'
	SELECT @YUN = ExchangeID FROM CustDB.dbo.Exchange WITH (NOLOCK) WHERE currency = 'YUN'
	
	IF (@LicenseeID = @KeenOceanID OR ISNULL(@LicenseeID, 0) = 0)
	BEGIN
		INSERT INTO @tbLicenseeCust (LicenseeID, CustID, RoleID, Currency, CurrencyName, [Description])
		SELECT LicenseeID, CustID, RoleID, @RMB, 'CNY', [Description] 
		FROM dbo.LicenseeCust WITH (NOLOCK) WHERE LicenseeID = @KeenOceanID AND Currency = @YUN
	END

	RETURN
END
GO
/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LAPLicenseeSel]
AS
/*
	Created: 20190102@Parsons
	Task : Launch new licensee
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20190102@Parsons: Launch new licensee
		- 20220623@Percy: Get more licensee information from OIC [RedmineID: #166504]
		- 20220818@Danny: edit sp to get data via DBLINK [RedmineID: #166504]

	Params:

	Explannation: EXEC LA_LAPLicenseeSel
*/
BEGIN
	SET NOCOUNT ON

	-- Base Currency List
	DECLARE @BaseCurrencyList TABLE (CurrencyId INT, CurrencyName VARCHAR(5))
	
	INSERT INTO @BaseCurrencyList (CurrencyId, CurrencyName)
	EXEC dbo.LA_SelBaseCurrency

	-- Return data
	SELECT
		l.LicenseeID			AS PartyId
		,l.LicenseeName			AS PartyName
		,l.BrandName
		,b.PartyId				AS BillingGroupId
		,b.PartyName			AS BillingGroupName
		,ol.InvoiceLanguage
		,bc.CurrencyId			AS BaseCurrency
	FROM dbo.Licensees l WITH(NOLOCK)
		LEFT JOIN dbo.OAS_Party p WITH(NOLOCK) ON l.LicenseeID = p.OldRefID AND p.PartyType IN (1, 5) -- Licensee
		LEFT JOIN DBOIC.bodb_OIC.dbo.Licensee ol WITH(NOLOCK) ON l.LicenseeName = ol.RegisteredLicenseeName
		LEFT JOIN DBOIC.bodb_OIC.dbo.LicenseeTypes olt WITH(NOLOCK) ON ol.TypeId = olt.TypeId
		LEFT JOIN dbo.OAS_Party b WITH(NOLOCK) ON olt.TypeName = b.PartyName AND b.PartyType IN (2, 3) -- Billing Group
		LEFT JOIN @BaseCurrencyList bc ON ol.InvoiceBaseCurrency = bc.CurrencyName
	WHERE p.PartyID IS NULL
END
GO
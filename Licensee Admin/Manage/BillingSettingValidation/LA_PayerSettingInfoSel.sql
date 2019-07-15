/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingInfoSel]
@PartyId INT = 0
AS
/*
	Created: 20190620@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190620@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ChargeRateInfo TABLE(FromParty INT, ToParty INT)
	DECLARE @LicenseeId INT = 0

	IF @PartyId <> 0 SELECT @LicenseeId = OldRefID FROM OAS_Party WITH(NOLOCK) WHERE PartyID = @PartyId	

	DECLARE @tblLicenseeCurrency AS TABLE(LicenseeId INT, CurrencyCount INT)
	INSERT INTO @tblLicenseeCurrency(LicenseeId, CurrencyCount)
	SELECT c.LicenseeID,COUNT(c.Currency)
	FROM dbo.LicenseeCust c WITH(NOLOCK)
	WHERE @LicenseeId = 0 OR c.LicenseeID = @LicenseeId AND c.Currency <> 20 -- test currency
	GROUP BY c.LicenseeID

	SELECT P.PartyID, p.PartyName, p.PartyType,
			ISNULL(d.BaseCurrencyId, 0)		AS BaseCurrencyId, 
			ISNULL(p.OldRefID, 0)			AS LicenseeId,   
			ISNULL(d.InvoiceLanguage, '')	AS InvoiceLanguage,
			ISNULL(c.CurrencyCount, 0)		AS CurrencyCount
	FROM OAS_Party p WITH(NOLOCK)
	INNER JOIN OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
	LEFT JOIN @tblLicenseeCurrency c ON c.LicenseeId = p.OldRefID
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID)
		AND p.PartyType NOT IN (2,3,4,5)
	--(1, 'Payer'),
	--(2, 'Reseller'),
	--(3, '3rd'),
	--(4, 'Biller'),
	--(5, 'Non-Official')
END
GO
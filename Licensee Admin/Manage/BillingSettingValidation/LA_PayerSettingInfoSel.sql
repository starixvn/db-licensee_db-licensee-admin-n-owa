/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190620@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON

	
	DECLARE @ChargeRateInfo TABLE(FromParty INT, ToParty INT)

	;WITH cte_ChargeRateInfo AS (
		SELECT DISTINCT FromParty, ToParty 
		FROM [dbo].[OAS_ChargeInfo] WITH(NOLOCK)
		WHERE ToParty IN (1,9,11,98) AND ToDate >= GETDATE()
	), cte_PartyBelongToGroups AS(
		SELECT FromParty, COUNT(ToParty) AS NumberOfGroups
		FROM cte_ChargeRateInfo 
		GROUP BY FromParty)

	SELECT P.PartyID, p.PartyName, p.PartyType,
			ISNULL(d.BaseCurrencyId, 0)		AS BaseCurrencyId, 
			ISNULL(p.OldRefID, 0)			AS OldRefID,   
			ISNULL(d.InvoiceLanguage, '')	AS InvoiceLanguage,
			CASE WHEN EXISTS(SELECT TOP 1 1 FROM dbo.f_SelLicenseeCust(0) AS lc WHERE ISNULL(p.OldRefID, 0) = lc.LicenseeID) THEN 1 ELSE 0 END AS HasNotOfferedCurrency,
			CASE WHEN ISNULL(pbg.NumberOfGroups, 0) > 1 THEN 1 ELSE 0 END AreBelongingMoreThanOneGroup 
	FROM OAS_Party p WITH(NOLOCK)
	INNER JOIN OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
	LEFT JOIN cte_PartyBelongToGroups pbg ON p.PartyID = pbg.FromParty
	WHERE @PartyId = 0 OR @PartyId = p.PartyID
END
GO
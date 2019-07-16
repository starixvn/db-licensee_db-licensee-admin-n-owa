/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_MinfeeSettingInfoSel]
@PartyId INT = 0
AS
/*
	Created: 20190626@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190626@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.PartyID, PartyName, PartyType, MAX(FromDate) AS FromDate, MAX(ToDate) AS ToDate, ProductID, 
				ISNULL(FeeTypeId, 0)			AS FeeTypeId, 
				ISNULL(pg.PartyGroupId, 0)		AS PartyGroupId, 
				ISNULL(pd.BaseCurrencyId, 0)	AS BaseCurrencyId, 
				ISNULL(mf.CurrencyId, 0)		AS CurrencyId
	FROM OAS_Party p WITH(NOLOCK) 
		INNER JOIN OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID 
		LEFT JOIN LA_MinFee mf WITH(NOLOCK) ON p.PartyID = mf.PartyId
		LEFT JOIN LA_PartyGroupAssignment pga WITH(NOLOCK) ON p.PartyID = pga.PartyId
		LEFT JOIN LA_PartyGroup pg WITH(NOLOCK) ON pg.PartyGroupId = pga.PartyGroupId
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID) AND (ToDate IS NULL OR ToDate >= GETDATE())
		  AND p.PartyID NOT IN (1,9,11,98)
		  AND pd.IsDeposit = 1
	GROUP BY p.PartyID, PartyName, PartyType, ProductID, 
				ISNULL(FeeTypeId, 0),
				ISNULL(pg.PartyGroupId, 0), 
				ISNULL(pd.BaseCurrencyId, 0), 
				ISNULL(mf.CurrencyId, 0)
END
GO
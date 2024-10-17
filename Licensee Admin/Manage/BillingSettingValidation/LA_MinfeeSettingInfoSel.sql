/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_MinfeeSettingInfoSel]
@PartyIds			VARCHAR(MAX)
AS
/*
	Created: 20190626@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190626@Parsons: Validate billing configuration [#109600]
	- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.PartyID, PartyName, PartyType, FromDate , ToDate, ProductID, pg.PartyGroupName,
				ISNULL(FeeTypeId, 0)			AS FeeTypeId, 
				ISNULL(pg.PartyGroupId, 0)		AS PartyGroupId, 
				ISNULL(pd.BaseCurrencyId, 0)	AS BaseCurrencyId, 
				ISNULL(mf.CurrencyId, 0)		AS CurrencyId,
				ISNULL(mf.MinFeeId, 0)			AS MinFeeId
	FROM OAS_Party p WITH(NOLOCK) 
		INNER JOIN OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID 
		LEFT JOIN LA_MinFee mf WITH(NOLOCK) ON p.PartyID = mf.PartyId
		LEFT JOIN LA_PartyGroupAssignment pga WITH(NOLOCK) ON p.PartyID = pga.PartyId
		LEFT JOIN LA_PartyGroup pg WITH(NOLOCK) ON pg.PartyGroupId = pga.PartyGroupId
	WHERE p.PartyId IN (SELECT value FROM STRING_SPLIT(@PartyIds,','))
		  AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
		  AND pd.IsDeposit = 1
END
GO
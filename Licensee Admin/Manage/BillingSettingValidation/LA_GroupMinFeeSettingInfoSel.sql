/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeSettingInfoSel]
@PartyIds			VARCHAR(MAX)
AS
/*
	Created: 20200708@Mason
	Task : Get Group Min Fee setting by party
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20200708@Mason: Implement Group Min Fee [#134492]
	- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0
	
	SELECT p.PartyID AS PartyId, 
			PartyName, 
			PartyType, 
			d.MinimumFee,
			d.ProductID AS ProductId,
			a.IsPrimary,
			ISNULL(h.GroupMinFeeID, 0) AS GroupMinFeeId,
			d.CurrencyId AS CurrencyId,
			h.Name AS GroupName,
			h.FromDate AS FromDate,
			h.ToDate AS ToDate,
			d.FromDate AS SettingFromDate,
			d.ToDate AS SettingToDate
	FROM dbo.OAS_Party p WITH (NOLOCK)
		LEFT JOIN dbo.LA_GroupMinFeeAssignment a ON p.PartyID = a.PartyID
		LEFT JOIN dbo.LA_GroupMinFeeHeader h ON a.GroupMinFeeID = h.GroupMinFeeID
		LEFT JOIN dbo.LA_GroupMinFeeDetail d ON a.GroupMinFeeID = d.GroupMinFeeID
	WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds,','))
			AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
			AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
END
GO
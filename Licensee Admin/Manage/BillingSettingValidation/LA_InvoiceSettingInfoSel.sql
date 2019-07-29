/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingInfoSel]
@PartyIds			VARCHAR(4000)
AS
/*
	Created: 20190624@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190624@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100))
	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	DECLARE @PartyHasProductBA AS TABLE(PartyId INT)
	INSERT INTO @PartyHasProductBA (PartyId)
	SELECT DISTINCT FromParty 
	FROM OAS_ChargeInfo ci WITH(NOLOCK)
	WHERE ci.ToDate >= GETDATE() AND ci.ToParty = 1 /*OW*/ AND ci.ProductID = 3 /*BA*/ 

	SELECT p.PartyID, p.PartyName, p.PartyType,
			ISNULL(ivs.ToPartyId, 0)		AS ToPartyId, 
			ISNULL(ivs.InvTypeId, 0)		AS InvTypeId, 
			ivs.ProductId					AS ProductId, 
			ISNULL(ivs.InvTempId, 0)		AS InvSettingTemplateId, 
			ISNULL(ivt.InvTemplateId, 0)	AS InvTemplateId,
			ISNULL(b.PartyId, 0)			AS BillerId, 
			ISNULL(pList.ParentId, 0)		AS ParentId,
			CASE WHEN pBA.PartyId IS NULL THEN 0 ELSE 1 END		AS HasProductBA
	FROM OAS_Party p WITH(NOLOCK) 
	LEFT JOIN LA_InvoiceSetting ivs WITH(NOLOCK) ON p.PartyID = ivs.FromPartyId
	LEFT JOIN LA_InvoiceTemplate ivt WITH(NOLOCK) ON ivs.InvTempId = ivt.InvTemplateId
	LEFT JOIN LA_BillerInfo b WITH(NOLOCK) ON ivs.ToPartyId = b.PartyId
	LEFT JOIN @PartyList pList ON P.PartyID = pList.PartyId
	LEFT JOIN @PartyHasProductBA pBA ON p.PartyID = pBA.PartyId
	WHERE p.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
			AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
			AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
END
GO
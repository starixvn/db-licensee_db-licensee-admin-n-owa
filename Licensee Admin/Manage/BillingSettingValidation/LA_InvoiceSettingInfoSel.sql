/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingInfoSel]
@PartyId INT = 0
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

	SELECT p.PartyID, p.PartyName, p.PartyType,
			ISNULL(ivs.ToPartyId, 0)		AS ToPartyId, 
			ISNULL(ivs.InvTypeId, 0)		AS InvTypeId, 
			ivs.ProductId					AS ProductId, 
			ISNULL(ivs.InvTempId, 0)		AS InvSettingTemplateId, 
			ISNULL(ivt.InvTemplateId, 0)	AS InvTemplateId,
			ISNULL(b.PartyId, 0)			AS BillerId 
	FROM OAS_Party p WITH(NOLOCK) 
	LEFT JOIN LA_InvoiceSetting ivs WITH(NOLOCK) ON p.PartyID = ivs.FromPartyId
	LEFT JOIN LA_InvoiceTemplate ivt WITH(NOLOCK) ON ivs.InvTempId = ivt.InvTemplateId
	LEFT JOIN LA_BillerInfo b WITH(NOLOCK) ON ivs.ToPartyId = b.PartyId
	WHERE @PartyId = 0 OR @PartyId = p.PartyID 
			AND p.PartyID NOT IN (1,9,11,98, -- ParentId of deposit
												25,30,324) -- Credit 
END
GO
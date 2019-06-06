/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceReferenceGet]
	@BillerId		INT,
	@PayerId 		INT,
	@Environment	VARCHAR(10)
AS
/*	
	Created: 2017.07.19 - Scofield.Huynh [#79905]
	DB:		DBCUST.bodb_Licensee	

	Revisions:
		- 20180131@Bruce: support credit note for setup fee [#90274]
*/
BEGIN
	SELECT OfficialInvoiceNo	AS InvoiceNo,
		InvoiceHeaderId			AS InvoiceId,
		InvoiceType
	FROM LA_InvoiceHeader WITH(NOLOCK)
	WHERE InvoiceType IN (1, 3, 7) -- Software Fee, Rebate, setupfee
		AND StatusId = 0 -- normal
		AND PartyId = @PayerId 
		AND BillerId = @BillerId
		AND Environment = @Environment
	ORDER BY CreatedDateTime
END
GO
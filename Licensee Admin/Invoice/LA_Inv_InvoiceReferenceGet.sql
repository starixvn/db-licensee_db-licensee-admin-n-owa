USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceReferenceGet]
	@BillerId		INT,
	@PayerId 		INT,
	@Environment	VARCHAR(10)
AS
/*	
	Created: 2017.07.19 - Scofield.Huynh [#79905]
	DB:		DBLIC/bodb_Licensee	

	Revision:
		20180131@Bruce: include setupfee
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

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceReferenceGet] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceReferenceGet] TO vnteam
GO
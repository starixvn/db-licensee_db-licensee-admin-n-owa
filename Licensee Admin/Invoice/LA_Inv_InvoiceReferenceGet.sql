USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceReferenceGet]
	@BillerId		INT,
	@PayerId 		INT,
	@InvoiceType	INT = 0
AS
/*	
	Created: 2017.07.19 - Scofield.Huynh [#79905]		
	DB:		DBLIC/bodb_Licensee	
*/
BEGIN
	SELECT OfficialInvoiceNo InvoiceNo, InvoiceType
	FROM LA_InvoiceHeader WITH(NOLOCK)
	WHERE BillerId = @BillerId 
		AND StatusId = 0 -- normal
		AND PartyId = @PayerId 
		AND ((@InvoiceType = 0 AND InvoiceType IN (1, 3)) OR @InvoiceType = InvoiceType) -- Software Fee, Rebate
	ORDER BY CreatedDateTime
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceReferenceGet] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceReferenceGet] TO vnteam
GO
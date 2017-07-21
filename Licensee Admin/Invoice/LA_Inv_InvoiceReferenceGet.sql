USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceReferenceGet]
	@BillerId		INT,
	@PayerId 		INT	
AS
/*	
	Created: 2017.07.19 - Scofield.Huynh [#79905]		
	DB:		DBLIC/bodb_Licensee	
*/
BEGIN
	SELECT InvoiceNumber, InvoiceType
	FROM LA_InvoiceHeader
	WHERE BillerId = @BillerId AND PartyId = @PayerId 
		AND InvoiceType IN (1, 3) -- Software Fee, Rebate
END

GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceReferenceGet] TO bodbAdminNet
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceReferenceGet] TO vnteam
GO
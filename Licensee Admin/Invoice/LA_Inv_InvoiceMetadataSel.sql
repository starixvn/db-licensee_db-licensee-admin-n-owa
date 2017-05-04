USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].LA_Inv_InvoiceMetadataSel
	@InvoiceIdString VARCHAR(8000)
AS
/*	Header:
	Created: 2017.04.26 - Bruce
	Task : Get invoice header by id
	DB: DB052.bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT InvoiceHeaderId, InvoiceData, InvoicePath, Environment
	FROM dbo.LA_InvoiceHeader
	WHERE InvoiceHeaderId IN(SELECT val FROM dbo.strSplit(@InvoiceIdString, ','))
	
END

GO
GRANT EXECUTE ON [dbo].LA_Inv_InvoiceMetadataSel TO bodbAdminNet
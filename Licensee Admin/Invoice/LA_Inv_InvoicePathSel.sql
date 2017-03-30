USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LA_Inv_InvoicePathSel]
	@InvoiceId INT
AS
/*	Header:
	Created: 20170330@Bruce
	Task :	Get invoice metadata
	DB:		DBLIC/bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON
	SELECT ISNULL(InvoicePath, '') InvoicePath
	FROM dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @InvoiceId
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoicePathSel] TO bodbAdminNet


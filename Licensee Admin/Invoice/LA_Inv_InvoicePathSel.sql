USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoicePathSel]
	@InvoiceId INT
AS
/*	
	Created: 20170330@Bruce
	Task :	Get invoice metadata [#74096]
	DB:		DBLIC/bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON
	SELECT ISNULL(InvoicePath, '') InvoicePath
	FROM dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @InvoiceId
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoicePathSel] TO bodbAdminNet
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoicePathSel] TO vnteam
GO

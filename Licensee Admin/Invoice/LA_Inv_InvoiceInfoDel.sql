USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoDel]
	@InvoiceHeaderId INT
AS

/*  Header:
	Created: 2017.08.24@Bruce
	Task : Delete invalid invoice
	DB: DB052.bodb_Licensee

	Revisions:
		20170824@Bruce: Create New SP to delete Invoice [RedmineID: #76410]
*/

BEGIN
	SET NOCOUNT ON
	
	DELETE dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @InvoiceHeaderId
	DELETE dbo.LA_InvoiceStatement WHERE InvoiceHeaderId = @InvoiceHeaderId
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoDel] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceInfoDel] TO vnteam
GO

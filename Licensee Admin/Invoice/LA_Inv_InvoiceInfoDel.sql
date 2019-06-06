/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoDel]
	@InvoiceHeaderId INT
AS

/*  Header:
	Created: 2017.08.24@Bruce
	Task : Delete invalid invoice
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20170824@Bruce: Create New SP to delete Invoice [RedmineID: #76410]
*/

BEGIN
	SET NOCOUNT ON
	
	DELETE dbo.LA_InvoiceHeader WITH (ROWLOCK, UPDLOCK) WHERE InvoiceHeaderId = @InvoiceHeaderId
	DELETE dbo.LA_InvoiceStatement WITH (ROWLOCK, UPDLOCK) WHERE InvoiceHeaderId = @InvoiceHeaderId
END
GO
/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].LA_Inv_InvoiceFileGet
	@InvoiceId INT
AS
/*	Created: 20190121@Bruce
	Task : Get invoice pdf from DB
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190121@Bruce: Create SP [#96660]
*/

BEGIN
	SET NOCOUNT ON;
	SELECT FileData FROM dbo.LA_InvoiceFile WITH(NOLOCK) WHERE InvoiceHeaderId = @InvoiceId
END
GO
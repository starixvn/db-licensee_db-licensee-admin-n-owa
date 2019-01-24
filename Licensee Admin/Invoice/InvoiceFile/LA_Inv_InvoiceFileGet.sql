/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].LA_Inv_InvoiceFileGet (@InvoiceId INT)
AS
/*	Created: 20190121@Bruce
	Task : Get invoice pdf from DB
	DB: DB052/bodb_Licensee
	Revisions:
		- 20190121@Bruce: Create SP [#96660]
*/

BEGIN
	SET NOCOUNT ON;
	SELECT FileData FROM dbo.LA_InvoiceFile WITH(NOLOCK) WHERE InvoiceHeaderId = @InvoiceId
END
GO
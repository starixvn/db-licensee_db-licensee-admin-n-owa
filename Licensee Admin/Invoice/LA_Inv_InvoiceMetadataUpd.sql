/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceMetadataUpd]
	  @InvoiceId	INT
	, @InvoiceData	NVARCHAR(MAX)
	, @InvoicePath	NVARCHAR(255)
	, @Environment	VARCHAR(50)
	, @ErrCode	INT OUTPUT
	, @ErrMsg	VARCHAR(50) OUTPUT
AS

/*  
	Created: 20170330@Bruce
	Task : Update invoice metadata [#74096]
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20170330@Bruce: Initialize SP
*/
BEGIN
	SET NOCOUNT ON

	UPDATE dbo.LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK) SET
		InvoiceData = @InvoiceData,
		InvoicePath = @InvoicePath,
		Environment = @Environment
	WHERE InvoiceHeaderId = @InvoiceId
END
GO
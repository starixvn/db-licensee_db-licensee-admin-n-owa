USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceMetadataUpd]
	  @InvoiceId	INT
	, @InvoiceData	NVARCHAR(MAX)
	, @InvoicePath	NVARCHAR(255)
	, @ErrCode	INT OUTPUT
	, @ErrMsg	VARCHAR(50) OUTPUT
AS

/*  Header:
	Created: 20170330@Bruce
	Task : Update invoice metadata
	DB: DB052.bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON

	UPDATE dbo.LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK) SET
		InvoiceData = @InvoiceData,
		InvoicePath = @InvoicePath
	WHERE InvoiceHeaderId = @InvoiceId
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceMetadataUpd] TO bodbAdminNet
GO

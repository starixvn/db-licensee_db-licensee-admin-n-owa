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
	, @Environment	VARCHAR(50)
	, @ErrCode	INT OUTPUT
	, @ErrMsg	VARCHAR(50) OUTPUT
AS

/*  
	Created: 20170330@Bruce
	Task : Update invoice metadata [#74096]
	DB: DB052.bodb_Licensee
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

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceMetadataUpd] TO bodbAdminNet
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceMetadataUpd] TO vnteam
GO

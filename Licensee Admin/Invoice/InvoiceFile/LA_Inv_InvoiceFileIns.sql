/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].LA_Inv_InvoiceFileIns (
	@InvoiceId	INT,
	@Data				VARBINARY(MAX),
	@ErrMsg				VARCHAR(4000) = ''	OUTPUT,
	@ErrCode			INT = 0				OUTPUT
)
AS
/*	Created: 20190121@Bruce
	Task : Save invoice pdf to DB
	DB: DB052/bodb_Licensee
	Revisions:
		- 20190121@Bruce: Create SP [#96660]
*/

BEGIN
	SET NOCOUNT ON;

	SELECT @ErrCode = 0, @ErrMsg = ''

	IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceFile WHERE InvoiceHeaderId = @InvoiceId)
	BEGIN
		SELECT @ErrCode = 601, @ErrMsg = 'Invoice file already exists.'
	END
	ELSE
	BEGIN
		INSERT INTO dbo.LA_InvoiceFile(InvoiceHeaderId, FileData) VALUES (@InvoiceId, @Data)

		IF (@@ERROR <> 0) SELECT @ErrCode = @@ERROR, @ErrMsg = ERROR_MESSAGE()
	END
END
GO
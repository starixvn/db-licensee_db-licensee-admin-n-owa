USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceStatusUpd]
	@InvoiceId		INT,
	@StatusId		INT,
	@VoidTime		SMALLDATETIME,
	@UserId			INT,
	@LoginIp		VARCHAR(20),
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			VARCHAR(1000) = '' OUTPUT
AS
/*	Header:
	Created: 20170607@Bruce
	Task :	Void invoice
	DB:		DBLIC/bodb_Licensee

	Revisions:
		20170607@Bruce: Create new SP for void invoice [RedmineID: #76411]
*/
BEGIN
	SET NOCOUNT ON

	IF EXISTS (SELECT 1 FROM dbo.LA_InvoiceHeader WITH(NOLOCK) WHERE InvoiceHeaderId = @InvoiceId AND StatusId = -1) --void
	BEGIN
		SELECT @ErrCode = 1000, @ErrMsg = 'This invoice has already been voided!'
		RETURN
	END

	UPDATE dbo.LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK)
	SET StatusId = @StatusId, UpdatedBy = @UserId, UpdatedDateTime=@VoidTime
	WHERE InvoiceHeaderId = @InvoiceId

	UPDATE dbo.LA_InvoiceStatement WITH(ROWLOCK, UPDLOCK)
	SET StatusID = @StatusId
	WHERE InvoiceHeaderId = @InvoiceId

	SELECT @ErrCode = 0, @ErrMsg = ''
END

GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceStatusUpd] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceStatusUpd] TO vnteam
GO
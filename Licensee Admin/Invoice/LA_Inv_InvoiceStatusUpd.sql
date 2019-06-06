/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
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
	DB:		DBCUST.bodb_Licensee

	Revisions:
		- 20170607@Bruce: Create new SP for void invoice [RedmineID: #76411]
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
/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[LA_Statement_SOAFileIns]
	@InvoiceId			INT,
	@PartyID			INT,
	@Data				VARBINARY(MAX),
	@UserID				INT,
	@LoginIP			VARCHAR (50)	= '',
	@ErrMsg				VARCHAR(4000)	= ''		OUTPUT,
	@ErrCode			INT				= 0			OUTPUT,
	@Environment		VARCHAR(10)		= 'LOCAL',
	@SOAId				INT				= 0			OUTPUT
AS
/*  Header:
	Created: 2014.04.09 - Danny
	Task : Save SOA file
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20240409@Danny: Save SOA file
*/

BEGIN
	SET NOCOUNT ON;

	SELECT @ErrCode = 0, @ErrMsg = ''

	IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_SOAFile WHERE InvoiceHeaderId = @InvoiceId)
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = 'SOA file already exists.'
	END
	ELSE
	BEGIN
		INSERT INTO dbo.LA_SOAFile(InvoiceHeaderId, PartyID,  FileData, CreatedDate, CreatedBy, Environment) VALUES (@InvoiceId, @PartyID ,@Data, GETDATE(), @UserID, @Environment)
		SET @SOAId = SCOPE_IDENTITY()

		IF (@@ERROR <> 0) 
		BEGIN
			SELECT @ErrCode = @@ERROR, @ErrMsg = ERROR_MESSAGE()
			-- Rollback Invoice 
			IF @InvoiceId IS NOT NULL
			BEGIN
				DELETE FROM LA_InvoiceFile WITH(ROWLOCK, UPDLOCK) WHERE InvoiceHeaderId = @InvoiceId
				DELETE FROM LA_InvoiceStatement WITH(ROWLOCK, UPDLOCK) WHERE InvoiceHeaderId = @InvoiceId
				DELETE FROM LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK) WHERE InvoiceHeaderId = @InvoiceId
			END
		END
	END
END
GO
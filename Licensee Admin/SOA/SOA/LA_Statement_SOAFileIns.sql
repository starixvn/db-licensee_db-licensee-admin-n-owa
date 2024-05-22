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
	@SOAId				INT				= 0			OUTPUT,
	@BillerId			INT				= NULL,
	@SOAType			TINYINT			= NULL, --  0: SOA for invoice, 1: SOA for reseller
	@CurrencyId			INT				= NULL,
	@StatementDate		DATETIME		= NULL,
	@StatementFileName  NVARCHAR(255)	= ''		OUTPUT
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
	DECLARE @LicenseeName VARCHAR(50)

	IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_SOAFile WHERE InvoiceHeaderId = @InvoiceId)
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = 'SOA file already exists.'
	END
	ELSE
	BEGIN
		SELECT @LicenseeName = PartyName FROM OAS_Party WITH(NOLOCK) WHERE PartyID = @PartyID
		
		IF @InvoiceId IS NOT NULL
		BEGIN
			SELECT  @BillerId = u.BillerId,
					@CurrencyId = u.CurrencyId,
					@StatementDate = u.InvoiceDate,
					@SOAType =  CASE-- WHEN u.InvoiceType IN (1,6,7) OR x.InvoiceType IN (1,6,7) THEN 0
									 WHEN u.InvoiceType  = 3 OR x.InvoiceType = 3 THEN 1
									 ELSE 0
									END
			FROM LA_InvoiceHeader u WITH(NOLOCK) 
			OUTER APPLY (
				SELECT TOP 1  h.InvoiceType
				FROM LA_InvoiceStatement st WITH(NOLOCK)  
				INNER JOIN LA_InvoiceHeader h WITH(NOLOCK)  ON  st.RefNo = h.OfficialInvoiceNo AND h.StatusId <> -1
				WHERE st.InvoiceHeaderId = u.InvoiceHeaderId AND u.InvoiceType IN (4,5)
			) x
			WHERE u.InvoiceHeaderId = @InvoiceId

			SELECT @StatementFileName = 'Statement.re.'+ @LicenseeName + '.'+ FORMAT(@StatementDate,'yyyy.MM.dd') + CASE WHEN @SOAType = 0 THEN '' ELSE '.Rebates' END + '.pdf'
 
		END

		INSERT INTO dbo.LA_SOAFile(InvoiceHeaderId, PartyID,  FileData, CreatedDate, CreatedBy, Environment, FileName, BillerId, CurrencyId, StatementDate, SOAType) 
		VALUES (@InvoiceId, @PartyID ,@Data, GETDATE(), @UserID, @Environment, @StatementFileName, @BillerId, @CurrencyId, @StatementDate, @SOAType)

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
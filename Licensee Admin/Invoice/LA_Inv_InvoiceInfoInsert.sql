USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoInsert]
	  @BillerId				INT
	, @PayerId				INT
	, @InvoiceSymbol		NVARCHAR(20) = ''
	, @InvoiceNumber		INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @DueDate				DATETIME
	, @Amount				MONEY
	, @InvoiceType			SMALLINT
	, @Note					NVARCHAR(200)
	, @InvoiceDetailXml		NVARCHAR(MAX)
	, @IsSeparateProduct	BIT = 0
	, @UserID				INT
	, @LoginIP				VARCHAR (50) = ''
	, @HostingFeeMaxPCU		INT = 0
	, @HostingFeeRateAmount	MONEY = 0
	, @HostingFeeIsWaived	BIT = 0
	, @Environment			VARCHAR(20)
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @NewInvoiceNumber		INT						OUTPUT
	, @NewInvoiceId			INT						OUTPUT
AS

/*  Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice
	DB: DB052.bodb_Licensee

	Revisions:
		+ 20150806@Bravo: Save invoice
		+ 20151019@Victor: Support Chinese on Invoice's text fields
		+ 20160718@Bruce: Hosting fees - Insert hosting fees info
		+ 20170421@Bruce: Add environment filter
		+ 20170608@Bruce: Save details, reuse invoice no of voided invoice [#76411]

*/

BEGIN
	SET NOCOUNT ON

	DECLARE 
		@startRun		DATETIME, 
		@endRun			DATETIME, 
		@duration		INT, 
		@logSPData		NVARCHAR(MAX), 
		@logSPDataOld	NVARCHAR(MAX), 
		@xml			XML

	SET @startRun = GETDATE()

	IF ISNULL(@BillerId, 0) = 0
		OR ISNULL(@PayerId,0) = 0
		OR ISNULL(@InvoiceSymbol, '') = ''
		OR ISNULL(@InvoiceNumber, 0) <= 0
		OR ISNULL(@DueDate, '') = ''
		OR ISNULL(@InvoiceDetailXml, '') = ''
		OR @Amount IS NULL
		OR ISNULL(@InvoiceType, 0) <= 0
		OR ISNULL(@UserID, 0) = 0
		OR ISNULL(@Environment,'') = ''
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'Invalid invoice header inputs.'
		RETURN
	END

	-- Region: Check business logic: If invoice number exists, re-generate Invoice Number.
	-- if existed then get max(invoicenumber) + 1
	IF EXISTS (	SELECT	1
				FROM dbo.LA_InvoiceHeader WITH(NOLOCK)
				WHERE InvoiceSymbol = @InvoiceSymbol
					AND InvoiceNumber = @InvoiceNumber
					AND Environment = @Environment
					AND StatusId = 0 -- 0: normal, -1: void
	)
	BEGIN
		SELECT	@InvoiceNumber = (MAX(InvoiceNumber) + 1)
		FROM	dbo.LA_InvoiceHeader WITH(NOLOCK)
		WHERE	InvoiceSymbol = @InvoiceSymbol AND Environment = @Environment AND StatusId = 0
	END

	IF(@InvoiceNumber IS NULL)
	BEGIN
		SET @InvoiceNumber = 1
	END
	-- End Region

	-- Region: Insert data to Invoice Header
	DECLARE @CurrencyId INT = ISNULL((
		SELECT TOP 1 BaseCurrencyId
		FROM dbo.OAS_PartyDetail WITH(NOLOCK)
		WHERE PartyID = @PayerId), 6) -- default EUR

	BEGIN TRY
		DECLARE @CurrentDateTime DATETIME = GETDATE()
		DECLARE @InvoiceNo VARCHAR(50) =  CAST(@InvoiceNumber AS VARCHAR(10))
		SET @InvoiceNo = @InvoiceSymbol + (CASE WHEN @InvoiceNumber < 100 THEN RIGHT('000' + @InvoiceNo,3) ELSE @InvoiceNo END)

		DECLARE @InvoiceTypeList TABLE(InvoiceTypeId TINYINT, InvoiceTypeName VARCHAR(10))
		INSERT INTO @InvoiceTypeList VALUES (1,'SW'),(2,'BA'),(3,'RB'),(4,'CN'),(5,'DN'),(6,'HF'),(7,'SF')

		DECLARE @InvoiceNoCount INT = (
			SELECT COUNT(1) 
			FROM dbo.LA_InvoiceHeader WITH(NOLOCK) 
			WHERE InvoiceNumber = @InvoiceNumber AND InvoiceSymbol = @InvoiceSymbol AND Environment = @Environment
		)
		--{environment}-{invoice-type}-{invoice-number}-{create-date}-{gen-number}.pdf
		DECLARE @InvoiceFileName VARCHAR(255) = (
			SELECT @Environment + '-' + InvoiceTypeName + '-' + @InvoiceNo + '-' + CONVERT(varchar(50),@CurrentDateTime, 112) + '-' + CAST((@InvoiceNoCount + 1) AS VARCHAR(10)) + '.pdf'
			FROM @InvoiceTypeList WHERE InvoiceTypeId = @InvoiceType
		)

		INSERT	INTO dbo.LA_InvoiceHeader (BillerId, PartyId, CurrencyId, InvoiceSymbol, InvoiceNumber, FromDate, ToDate, InvoiceDate, DueDate, Amount, InvoiceType, StatusId, Note, HasSent, HasDeleted, CreatedBy, CreatedDateTime, IsSeparateProduct, MaxPCU, RateAmount, IsWaived, InvoicePath, Environment)
		VALUES
		(
				@BillerId,
				@PayerId,
				@CurrencyId,
				@InvoiceSymbol,
				@InvoiceNumber,
				@FromDate,
				@ToDate,
				@CurrentDateTime,
				@DueDate,
				@Amount,
				@InvoiceType,
				0,
				@Note,
				0,
				0,
				@UserID,
				@CurrentDateTime,
				@IsSeparateProduct,
				@HostingFeeMaxPCU,
				@HostingFeeRateAmount,
				@HostingFeeIsWaived,
				@InvoiceFileName,
				@Environment
		)
	END TRY
	BEGIN CATCH
		IF(@@ERROR <> 0)
		BEGIN
			SELECT @ErrCode = 3, @ErrMsg = 'Insert invoice failed.' -- System error
			RETURN
		END
	END CATCH
	DECLARE @CurrentInvoiceHeaderId BIGINT = SCOPE_IDENTITY()
	-- End Region

	-- Region: Insert data to Invoice Detail
	DECLARE @Detail AS TABLE(
		[Description]	NVARCHAR(200),
		Reference		NVARCHAR(100),
		ProductId		INT,
		Amount			MONEY,
		AmountType		TINYINT
	)
	BEGIN TRY
		DECLARE @idoc AS INT						
		EXEC	sp_xml_preparedocument @idoc OUTPUT, @InvoiceDetailXml			
		INSERT INTO @Detail([Description],Reference,ProductId,Amount,AmountType)
		SELECT 
			CAST([Description]	AS NVARCHAR(200)),
			CAST(Reference		AS NVARCHAR(100)),
			CAST(ProductId		AS INT),
			CAST(InvoiceAmount	AS MONEY),
			CAST(AmountType		AS TINYINT)
		FROM OPENXML(@idoc, 'InvoiceDetails/InvoiceDetail')
		WITH (
			[Description]	NVARCHAR(200) 'Description',
			Reference		NVARCHAR(100) 'Reference',
			ProductId		VARCHAR(10) 'ProductId',
			InvoiceAmount	VARCHAR(20) 'InvoiceAmount',
			AmountType		VARCHAR(10) 'AmountType'
		)
		EXEC sp_xml_removedocument @idoc		
						
		INSERT	INTO dbo.LA_InvoiceDetail(InvoiceHeaderId,[Description],Reference,ProductId,InvoiceAmount,AmountType)
		SELECT	@CurrentInvoiceHeaderId,[Description],Reference,ProductId,Amount,AmountType
		FROM	@Detail			
	END TRY
	BEGIN CATCH        	
		SELECT	@ErrCode = 2, @ErrMsg = 'Invalid invoice detail inputs.'
		RETURN
	END CATCH
	-- End Region

	SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully.', @NewInvoiceNumber = @InvoiceNumber, @NewInvoiceId = @CurrentInvoiceHeaderId

	-- Region: Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SET @xml = (
			SELECT @CurrentInvoiceHeaderId AS '@hid'
				, @BillerId			AS '@b'
				, @PayerId			AS '@p'
				, @CurrencyId		AS '@c'
				, @InvoiceSymbol	AS '@is'
				, @InvoiceNumber	AS '@in'
				, @CurrentDateTime	AS '@ivd'
				, @DueDate			AS '@dd'
				, @Amount			AS '@amt'
				, @InvoiceType		AS '@ivt'
				, 0					AS '@stt'
				, @Note				AS '@n'
				, 0					AS '@hs'
				, 0					AS '@hd'
				, @UserID			AS '@cb'
				, @CurrentDateTime	AS '@crd'
				, @CurrentDateTime	AS '@upd'
				, (SELECT 
					@CurrentInvoiceHeaderId AS '@hid'
					, [Description]			AS '@d'
					, Reference				AS '@r'
					, ProductId				AS '@pr'
					, Amount				AS '@amt'
					, AmountType			AS '@at'
				FROM @Detail
				FOR XML PATH('d'), TYPE)
			FOR XML PATH('h'), TYPE)

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_Inv_InvoiceInfoInsert'

	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog @UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_Inv_InvoiceInfoInsert'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = @logSPDataOld
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP @UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = @logSPDataOld
			, @duration = @duration
	END CATCH
	-- End Region
END

GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoInsert] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceInfoInsert] TO vnteam
GO

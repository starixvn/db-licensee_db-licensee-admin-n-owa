USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoInsert]
	  @BillerId				INT
	, @PartyId				INT
	, @InvoiceSymbol		NVARCHAR(20)
	, @InvoiceNumber		INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @DueDate				DATETIME
	, @Amount				MONEY
	, @InvoiceTypeId		SMALLINT
	, @Note					NVARCHAR(200) = ''
	, @StatementXml			NVARCHAR(MAX)
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
	, @InvoiceFileName		NVARCHAR(200)	= ''	OUTPUT
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
		+ 20170721@Scofield: Update to save data to InvoiceStatement [#79905]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE 
		@startRun		DATETIME, 
		@endRun			DATETIME, 
		@duration		INT, 
		@logSPData		NVARCHAR(MAX) 

	SET @startRun = GETDATE()

	IF ISNULL(@BillerId, 0) = 0
		OR ISNULL(@PartyId,0) = 0
		OR ISNULL(@InvoiceSymbol, '') = ''
		OR ISNULL(@InvoiceNumber, 0) <= 0
		OR ISNULL(@DueDate, '') = ''
		OR ISNULL(@StatementXml, '') = ''
		OR @Amount IS NULL
		OR ISNULL(@InvoiceTypeId, 0) <= 0
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
		WHERE PartyID = @PartyId), 6) -- default EUR

	BEGIN TRY
		DECLARE @CurrentDateTime DATETIME = GETDATE()

		-- generate Invoice No.
		DECLARE @InvoiceNo VARCHAR(50) =  CAST(@InvoiceNumber AS VARCHAR(10))
		SET @InvoiceNo = @InvoiceSymbol + (CASE WHEN @InvoiceNumber < 100 THEN RIGHT('000' + @InvoiceNo,3) ELSE @InvoiceNo END)

		DECLARE @InvoiceTypeList TABLE(InvoiceTypeId TINYINT, InvoiceTypeName VARCHAR(10))
		INSERT INTO @InvoiceTypeList VALUES (1,'SW'),(2,'BA'),(3,'RB'),(4,'CN'),(5,'DN'),(6,'HF'),(7,'SF')

		-- generate filename
		DECLARE @InvoiceNoCount INT = (
			SELECT COUNT(1) 
			FROM dbo.LA_InvoiceHeader WITH(NOLOCK) 
			WHERE InvoiceNumber = @InvoiceNumber AND InvoiceSymbol = @InvoiceSymbol AND Environment = @Environment
		)
		--{environment}-{invoice-type}-{invoice-number}-{create-date}-{gen-number}.pdf
		SET @InvoiceFileName = (
			SELECT @Environment + '-' + InvoiceTypeName + '-' + @InvoiceNo + '-' + CONVERT(varchar(50),@CurrentDateTime, 112) + '-' + CAST((@InvoiceNoCount + 1) AS VARCHAR(10)) + '.pdf'
			FROM @InvoiceTypeList WHERE InvoiceTypeId = @InvoiceTypeId
		)

		INSERT	INTO dbo.LA_InvoiceHeader (BillerId, PartyId, CurrencyId, InvoiceSymbol, InvoiceNumber, FromDate, ToDate, InvoiceDate, DueDate, Amount, InvoiceType, StatusId, Note, HasSent, HasDeleted, CreatedBy, CreatedDateTime, IsSeparateProduct, MaxPCU, RateAmount, IsWaived, InvoicePath, Environment, OfficialInvoiceNo)
		VALUES
		(
				@BillerId,
				@PartyId,
				@CurrencyId,
				@InvoiceSymbol,
				@InvoiceNumber,
				@FromDate,
				@ToDate,
				@CurrentDateTime,
				@DueDate,
				@Amount,
				@InvoiceTypeId,
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
				@Environment,
				@InvoiceNo
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
	DECLARE @Settlements AS TABLE(
		[Description]	NVARCHAR(200),
		Amount			MONEY,
		ItemType		TINYINT,
		Reference		NVARCHAR(100),
		Id				INT IDENTITY(1,1) NOT NULL
	)
	BEGIN TRY
		DECLARE @WrongInvoiceNo NVARCHAR(200) 
		DECLARE @idoc AS INT						
		EXEC	sp_xml_preparedocument @idoc OUTPUT, @StatementXml			
		INSERT INTO @Settlements([Description],Amount,ItemType,Reference)
		SELECT 
			[Description],
			CAST(Amount		AS MONEY),
			CAST(ItemType	AS TINYINT),
			Reference
		FROM OPENXML(@idoc, 'Statements/Statement')
		WITH (
			[Description]	NVARCHAR(200) 'Description',
			Amount			VARCHAR(20) 'Amount',
			ItemType		VARCHAR(10) 'ItemType',
			Reference		VARCHAR(100) 'Reference'
		)
		EXEC sp_xml_removedocument @idoc
		
		-- credit note = 4
		-- debit note  = 5
		IF @InvoiceTypeId = 4 OR @InvoiceTypeId = 5
		BEGIN
			-- verify statements
			SELECT s.*, h.InvoiceType INTO #StatementsHeader
			FROM @Settlements s
			LEFT JOIN dbo.LA_InvoiceHeader h on s.Reference = h.OfficialInvoiceNo 
				AND h.StatusId = 0 -- normal invoice
				AND h.PartyId = @PartyId
				AND h.BillerId = @BillerId

			-- wrong invoice no
			SET @WrongInvoiceNo = STUFF((
				SELECT ',', '''' + s.Reference + ''''
				FROM #StatementsHeader s WHERE s.InvoiceType IS NULL
				FOR XML PATH('')
			),1,1,'')

			IF @WrongInvoiceNo IS NOT NULL
			BEGIN
				DELETE dbo.LA_InvoiceHeader WHERE InvoiceHeaderId=@CurrentInvoiceHeaderId
				SELECT	@ErrCode = 4, @ErrMsg = 'Unknown Invoice No. ' + @WrongInvoiceNo
				RETURN
			END

			-- update itemtype
			-- invoice type: data fee: 1      -  rebate: 3
			-- item type:    data fee: debit(11),credit(12)  -  rebate: debit(13),credit(14)
			--
			UPDATE s SET s.ItemType = (CASE WHEN sh.InvoiceType = 1 THEN
						CASE WHEN @InvoiceTypeId = 4 THEN 12 ELSE 11 END
					WHEN sh.InvoiceType = 3 THEN
						CASE WHEN @InvoiceTypeId = 4 THEN 14 ELSE 13 END
					ELSE -1
				END)
			FROM #StatementsHeader sh
			INNER JOIN @Settlements s ON s.Id = sh.Id

			DROP TABLE #StatementsHeader
		END

		-- wrong item type
		--
		SET @WrongInvoiceNo = STUFF((
			SELECT ',', '''' + s.Reference + ''''
			FROM @Settlements s
			LEFT JOIN dbo.LA_InvoiceTypeMapping m WITH(NOLOCK) ON m.InvItemTypeId = s.ItemType AND m.InvTypeId = @InvoiceTypeId
			WHERE m.InvItemTypeId IS NULL
			FOR XML PATH('')
		),1,1,'')

		IF @WrongInvoiceNo IS NOT NULL
		BEGIN
			DELETE dbo.LA_InvoiceHeader WHERE InvoiceHeaderId=@CurrentInvoiceHeaderId
			SELECT	@ErrCode = 5, @ErrMsg = 'Wrong Invoice No. ' + @WrongInvoiceNo + ' for this item type.'
			RETURN
		END
					
		INSERT INTO dbo.LA_InvoiceStatement(InvoiceHeaderId, InvItemTypeId, [Description], RefNo, RefPartyId, Income, Expense)
		SELECT @CurrentInvoiceHeaderId, d.ItemType, d.[Description], d.Reference, @PartyId,
			CASE WHEN it.GroupDB = 'Income' THEN d.Amount * it.SignDB ELSE NULL END AS Income,
			CASE WHEN it.GroupDB = 'Expense' THEN d.Amount * it.SignDB ELSE NULL END AS Expense
		FROM @Settlements d
		INNER JOIN LA_InvoiceItemType it ON d.ItemType = it.InvItemTypeId				
		
		UPDATE dbo.LA_InvoiceHeader WITH(ROWLOCK,UPDLOCK)
		SET Amount = (SELECT (SUM(ISNULL(Income, 0))- SUM(ISNULL(Expense, 0))) 
						FROM  dbo.LA_InvoiceStatement
						WHERE InvoiceHeaderId = @CurrentInvoiceHeaderId)
		WHERE InvoiceHeaderId = @CurrentInvoiceHeaderId
		
	END TRY
	BEGIN CATCH
		DELETE dbo.LA_InvoiceHeader WHERE InvoiceHeaderId=@CurrentInvoiceHeaderId
		SELECT	@ErrCode = 2, @ErrMsg = 'Invalid invoice detail inputs.'
		RETURN
	END CATCH
	-- End Region

	SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully.', @NewInvoiceNumber = @InvoiceNumber, @NewInvoiceId = @CurrentInvoiceHeaderId

	-- Region: Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	DECLARE @xml XML = (
		SELECT @CurrentInvoiceHeaderId AS '@hid'
			, @BillerId			AS '@b'
			, @PartyId			AS '@p'
			, @CurrencyId		AS '@c'
			, @InvoiceSymbol	AS '@is'
			, @InvoiceNumber	AS '@in'
			, @CurrentDateTime	AS '@ivd'
			, @DueDate			AS '@dd'
			, @Amount			AS '@amt'
			, @InvoiceTypeId	AS '@ivt'
			, 0					AS '@stt'
			, @Note				AS '@n'
			, 0					AS '@hs'
			, 0					AS '@hd'
			, @UserID			AS '@cb'
			, @CurrentDateTime	AS '@crd'
			, @CurrentDateTime	AS '@upd'
			, @InvoiceFileName	AS '@fn'
			, @IsSeparateProduct	AS '@sp'
			, @HostingFeeIsWaived	AS '@hfw'
			, @HostingFeeMaxPCU		AS '@hfpcu'
			, @HostingFeeRateAmount	AS '@hfam'
			, (SELECT 
				@CurrentInvoiceHeaderId AS '@hid'
				, [Description]			AS '@d'
				, Amount				AS '@amt'
				, ItemType				AS '@at'
				, Reference				AS '@rn'
			FROM @Settlements
			FOR XML PATH('d'), TYPE)
		FOR XML PATH('h'), TYPE)
	SET @logSPData = CAST(@xml AS NVARCHAR(MAX))

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
			, @OldData = ''
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP @UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = ''
			, @duration = @duration
	END CATCH
	-- End Region
END

GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoInsert] TO bodbAdminNet
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoiceInfoInsert] TO vnteam
GO
USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoInsert] 
	  @BillerId			INT
	, @PayerId			INT		
	, @InvoiceSymbol	NVARCHAR(20)		= ''
	, @InvoiceNumber	INT	
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @DueDate			DATETIME
	, @Amount			MONEY
	, @InvoiceType		SMALLINT
	, @Note				NVARCHAR(200)	
	, @InvoiceDetailXml NVARCHAR(MAX)
	, @IsSeparateProduct BIT			= 0
	, @UserID			INT
	, @LoginIP			VARCHAR (50)	= ''
	, @HostingFeeMaxPCU		INT = 0
	, @HostingFeeRateAmount	MONEY = 0
	, @HostingFeeIsWaived	BIT = 0
	, @ErrCode			INT				= 0		OUTPUT
	, @ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
	, @NewInvoiceNumber INT						OUTPUT
	, @NewInvoiceId		INT						OUTPUT
AS

/*  Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee

	Revisions:   
		+ 20150806@Bravo: Save invoice
		+ 20151019@Victor: Support Chinese on Invoice's text fields
	Params:		
		+ @InvoiceDetailXml: 
			<InvoiceDetails>
				<InvoiceDetail>
					<Description>Software & Data...</Description>
					<Reference></Reference>
					<ProductId>0</ProductId>
					<InvoiceAmount>900.12</InvoiceAmount>
					<AmountType>0</AmountType>
				</InvoiceDetail>
				<InvoiceDetail>
					<Description>Less: Discount...</Description>
					<Reference></Reference>
					<ProductId>1</ProductId>
					<InvoiceAmount>90.01</InvoiceAmount>
					<AmountType>0</AmountType>
				</InvoiceDetail>
				<InvoiceDetail>
					<Description>Less: Rebate...</Description>
					<Reference></Reference>
					<ProductId>2</ProductId>
					<InvoiceAmount>81.1</InvoiceAmount>
					<AmountType>2</AmountType>
				</InvoiceDetail>
			</InvoiceDetails>
*/
/*	Example:
	USE bodb_licensee
	declare @p2 nvarchar(1000)
	declare @p9 int
	declare @p4 int
	set @p9=2
	declare @p11 int
	set @p11=0
	exec LA_Inv_InvoiceInfoInsert @NewInvoiceId = @p4 output, @InvoiceNumber=9,@ErrMsg=@p2 output,@DueDate='2015-09-30 00:00:00',@Note='',@UserID=4,@InvoiceDetailXml='<InvoiceDetails><InvoiceDetail><Description>Software & Data Licensing & Data transmission fees for Jul 2015 
	(Sportsbook)</Description><Reference></Reference><ProductId>0</ProductId><InvoiceAmount>483.87</InvoiceAmount><AmountType>0</AmountType></InvoiceDetail><InvoiceDetail><Description>1</Description><Reference></Reference><ProductId>0</ProductId><InvoiceAmount>21.19</InvoiceAmount><AmountType>1</AmountType></InvoiceDetail><InvoiceDetail><Description>1</Description><Reference></Reference><ProductId>0</ProductId><InvoiceAmount>21.19</InvoiceAmount><AmountType>1</AmountType></InvoiceDetail><InvoiceDetail><Description>Software & Data Licensing & Data transmission fees for Jul 2015 (Number Game)</Description><Reference></Reference><ProductId>2</ProductId><InvoiceAmount>109.12</InvoiceAmount><AmountType>0</AmountType></InvoiceDetail><InvoiceDetail><Description>Software & Data Licensing & Data transmission fees for Jul 2015 (BA)</Description><Reference></Reference><ProductId>3</ProductId><InvoiceAmount>17.34</InvoiceAmount><AmountType>0</AmountType></InvoiceDetail><InvoiceDetail><Description>Software & Data Licensing & Data transmission fees for Jul 2015 (Virtual Sports)</Description><Reference></Reference><ProductId>5</ProductId><InvoiceAmount>1</InvoiceAmount><AmountType>0</AmountType></InvoiceDetail><InvoiceDetail><Description>1</Description><Reference></Reference><ProductId>-1</ProductId><InvoiceAmount>1</InvoiceAmount><AmountType>0</AmountType></InvoiceDetail><InvoiceDetail><Description>1</Description><Reference></Reference><ProductId>-1</ProductId><InvoiceAmount>1</InvoiceAmount><AmountType>1</AmountType></InvoiceDetail></InvoiceDetails>',@BillerId=115,@Amount=568.9500,@ErrCode=@p9 output,@FromDate='2015-07-01 00:00:00',@NewInvoiceNumber=@p11 output,@InvoiceSymbol='BHC',@ToDate='2015-07-31 00:00:00',@PayerId=24,@LoginIP='10.19.10.68',@InvoiceType=1
	select @p2, @p9, @p11, @p4
*/
BEGIN
	SET NOCOUNT ON	

	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld	NVARCHAR(MAX), @xml XML
	SET @startRun = GETDATE()
		
	IF	ISNULL(@BillerId, 0) > 0 
		AND ISNULL(@PayerId,0) > 0 		
		AND ISNULL(@InvoiceSymbol, '') <> ''
		AND ISNULL(@InvoiceNumber, 0) > 0
		AND ISNULL(@DueDate, '') <> ''
		AND ISNULL(@InvoiceDetailXml, '') <> ''
		AND @Amount IS NOT NULL
		AND ISNULL(@InvoiceType, 0) > 0
		AND ISNULL(@UserID, 0) > 0
	BEGIN
		-- Region: Check business logic: If invoice number exists, re-generate Invoice Number.
		IF EXISTS (	SELECT	1 
					FROM	dbo.LA_InvoiceHeader lih WITH(NOLOCK) 
					WHERE	lih.InvoiceSymbol = @InvoiceSymbol 
							AND lih.InvoiceNumber = @InvoiceNumber)
		BEGIN
			SELECT	@InvoiceNumber = (MAX(InvoiceNumber) + 1) 
			FROM	dbo.LA_InvoiceHeader lih WITH(NOLOCK) 
			WHERE	lih.InvoiceSymbol = @InvoiceSymbol
		END		
		
		IF(@InvoiceNumber IS NULL)
		BEGIN
			SET @InvoiceNumber = 1
		END
		-- End Region
		
		-- Region: Insert data to Invoice Header
		DECLARE @CurrencyId INT = 12	
		SET @CurrencyId = ISNULL((	SELECT	TOP 1 opd.BaseCurrencyId
									FROM	bodb_licensee.dbo.OAS_PartyDetail opd WITH(NOLOCK)	
									WHERE	opd.PartyID = @PayerId
								), 12)
		
		BEGIN TRY							
			DECLARE @CurrentDateTime DATETIME = GETDATE()
			INSERT	INTO dbo.LA_InvoiceHeader (
					BillerId,
					PartyId,
					CurrencyId,
					InvoiceSymbol,
					InvoiceNumber,
					FromDate,
					ToDate,
					InvoiceDate,
					DueDate,
					Amount,
					InvoiceType,
					StatusId,
					Note,
					HasSent,
					HasDeleted,
					CreatedBy,
					CreatedDateTime,
					UpdatedDateTime,
					IsSeparateProduct,
					MaxPCU,
					RateAmount,
					IsWaived)
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
					@CurrentDateTime,
					@IsSeparateProduct,
					@HostingFeeMaxPCU,
					@HostingFeeRateAmount,
					@HostingFeeIsWaived
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
		BEGIN TRY
			DECLARE @idoc AS INT
			DECLARE @xmlText NVARCHAR(MAX) = REPLACE(@InvoiceDetailXml, '&', '&amp;')
			DECLARE @Detail AS TABLE(
					[Description]	NVARCHAR(200),
					Reference	NVARCHAR(100),
					ProductId	INT,
					Amount		MONEY,
					AmountType	TINYINT)
						
			EXEC	sp_xml_preparedocument @idoc OUTPUT, @xmlText			
			INSERT	INTO @Detail([Description],Reference,ProductId,Amount,AmountType)
			SELECT 
					CAST([Description] AS NVARCHAR(200)),
					CAST(Reference AS NVARCHAR(100)),
					CAST(ProductId AS INT),
					CAST(InvoiceAmount AS MONEY),
					CAST(AmountType AS TINYINT)
			FROM	OPENXML(@idoc, 'InvoiceDetails/InvoiceDetail')
			WITH (
					[Description] NVARCHAR(200) 'Description',
					Reference NVARCHAR(100) 'Reference',
					ProductId VARCHAR(10) 'ProductId',
					InvoiceAmount VARCHAR(20) 'InvoiceAmount',
					AmountType VARCHAR(10) 'AmountType'
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
		
		-- Region: Rollback manual: delete inserted record in LA_InvoiceHeader & LA_InvoiceDetail 		
		IF @@ERROR <> 0
		BEGIN			
			DELETE FROM dbo.LA_InvoiceDetail WHERE InvoiceHeaderId = @CurrentInvoiceHeaderId
			DELETE FROM dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @CurrentInvoiceHeaderId
			
			SELECT @ErrCode = 3, @ErrMsg = 'Insert invoice failed.' -- System error
		END		
		ELSE
		BEGIN
			SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully.', @NewInvoiceNumber = @InvoiceNumber, @NewInvoiceId = @CurrentInvoiceHeaderId
		END
		-- End Region
		
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

		SET @logSpData = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')

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
	ELSE
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'Invalid invoice header inputs.'
		RETURN
	END
	
END

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoInsert] TO bodbAdminNet
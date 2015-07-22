USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceInfoInsert]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoInsert] 
	  @BillerId			INT
	, @PayerId			INT	
	, @CurrencyId		INT
	, @InvoiceSymbol	VARCHAR(20)
	, @InvoiceNumber	INT	
	, @DueDate			DATETIME
	, @Amount			MONEY
	, @InvoiceType		SMALLINT
	, @StatusId			SMALLINT
	, @Note				VARCHAR(200)	
	, @InvoiceDetailXml VARCHAR(1000)
	, @UserID			INT
	, @LoginIP			VARCHAR (50)	= ''
	, @ErrCode			INT				= 0		OUTPUT
	, @ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
WITH RECOMPILE
AS
SET NOCOUNT ON

BEGIN	
	IF	ISNULL(@BillerId, 0) > 0 
		AND ISNULL(@PayerId,0) > 0 
		AND ISNULL(@CurrencyId,0) > 0 
		AND ISNULL(@InvoiceSymbol,'') <> '' 
		AND ISNULL(@InvoiceNumber, 0) > 0
		AND @DueDate IS NOT NULL
		AND ISNULL(@Amount, 0) > 0
		AND ISNULL(@InvoiceType, 0) > 0
		AND ISNULL(@UserID, 0) > 0
	BEGIN
		-- Region: Check business logic
		IF EXISTS (	SELECT 1 FROM dbo.LA_InvoiceHeader lih WITH(NOLOCK) WHERE lih.InvoiceSymbol = @InvoiceSymbol AND lih.InvoiceNumber = @InvoiceNumber)
		BEGIN
			SELECT @InvoiceNumber = (MAX(InvoiceNumber) + 1) FROM dbo.LA_InvoiceHeader lih WITH(NOLOCK) WHERE lih.BillerId = @BillerId
		END		
		-- End Region
		
		-- Region: Insert data to Invoice Header
		DECLARE @CurrentDateTime DATETIME = GETDATE()
		INSERT INTO dbo.LA_InvoiceHeader (BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,DueDate,Amount,InvoiceType,StatusId,Note,HasSent,HasDeleted,CreatedBy,CreatedDateTime,UpdatedDateTime)
		VALUES
		(
			@BillerId, @PayerId, @CurrencyId, @InvoiceSymbol, @InvoiceNumber, @CurrentDateTime, @DueDate, @Amount, @InvoiceType, @StatusId, @Note, 0, 0, @UserID, @CurrentDateTime, @CurrentDateTime
		)
		DECLARE @CurrentInvoiceId BIGINT = @@IDENTITY
		-- End Region
		
		-- Region: Insert data to Invoice Detail
		DECLARE @idoc AS INT
		EXEC sp_xml_preparedocument @idoc OUTPUT, @InvoiceDetailXml
		
		INSERT INTO dbo.LA_InvoiceDetail(InvoiceHeaderId,ItemName,Reference,ProductId,Amount,FeeType)
		SELECT @CurrentInvoiceId,
			[Description],
			Reference,
			CAST(ProductId AS INT),
			CAST(InvoiceAmount AS MONEY),
			CAST(AmountType AS TINYINT)
		FROM OPENXML(@idoc, 'InvoiceDetails/InvoiceDetail')
		WITH (
			[Description] VARCHAR(200) 'Description',
			Reference VARCHAR(100) 'Reference',
			ProductId VARCHAR(10) 'ProductId',
			InvoiceAmount VARCHAR(20) 'InvoiceAmount',
			AmountType VARCHAR(10) 'AmountType'
		)
		EXEC sp_xml_removedocument @idoc
		
		IF @@ERROR <> 0
		BEGIN
			-- Rollback manual: delete inserted record in LA_InvoiceHeader & LA_InvoiceDetail
			DELETE FROM dbo.LA_InvoiceDetail WHERE InvoiceHeaderId = @CurrentInvoiceId
			DELETE FROM dbo.LA_InvoiceHeader WHERE InvoiceHeaderId = @CurrentInvoiceId
			
			SELECT @ErrCode = 1001, @ErrMsg = 'Insert invoice failed.'
		END		
		ELSE
		BEGIN
			SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully. Invoice Number = ' & @InvoiceNumber
		END
		-- End Region
		
		-- Region: Write Log		
		
		-- End Region
	END
	ELSE
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Invalid Inputs.'
		RETURN
	END
END
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
	, @NewInvoiceNumber INT						OUTPUT
AS
SET NOCOUNT ON
/*  
	 Created: 20150721@Bravo
	 Task : Create Invoice 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
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
BEGIN	
	IF	ISNULL(@BillerId, 0) > 0 
		AND ISNULL(@PayerId,0) > 0 
		AND ISNULL(@CurrencyId,0) > 0 
		AND ISNULL(@InvoiceSymbol,'') <> '' 
		AND ISNULL(@InvoiceNumber, 0) > 0
		AND ISNULL(@DueDate, '') <> ''
		AND ISNULL(@InvoiceDetailXml, '') <> ''
		AND ISNULL(@Amount, 0) > 0
		AND ISNULL(@InvoiceType, 0) > 0
		AND ISNULL(@UserID, 0) > 0
	BEGIN
		-- Region: Check business logic: If invoice number exists, re-generate Invoice Number.
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
		DECLARE @CurrentInvoiceHeaderId BIGINT = SCOPE_IDENTITY()
		-- End Region
		
		-- Region: Insert data to Invoice Detail
		BEGIN TRY
			DECLARE @idoc AS INT
			DECLARE @xmlText VARCHAR(1000) = REPLACE(@InvoiceDetailXml, '&', '&amp;')
			DECLARE @Detail AS TABLE(
				ItemName	VARCHAR(200),
				Reference	VARCHAR(100),
				ProductId	INT,
				Amount		MONEY,
				FeeType		TINYINT)
						
			EXEC sp_xml_preparedocument @idoc OUTPUT, @xmlText			
			INSERT INTO @Detail(ItemName,Reference,ProductId,Amount,FeeType)
			SELECT 
				CAST([Description] AS VARCHAR(200)),
				CAST(Reference AS VARCHAR(100)),
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
			
			IF EXISTS (SELECT 1 FROM @Detail WHERE ProductId < 0 OR Amount <= 0 OR FeeType < 0)
			BEGIN
				SELECT @ErrCode = 2, @ErrMsg = 'Invalid invoice detail inputs.'
        		RETURN
			END
			ELSE
			BEGIN
				INSERT INTO dbo.LA_InvoiceDetail(InvoiceHeaderId,ItemName,Reference,ProductId,Amount,FeeType)
				SELECT @CurrentInvoiceHeaderId,ItemName,Reference,ProductId,Amount,FeeType
				FROM @Detail
			END
        END TRY
        BEGIN CATCH
        	SELECT @ErrCode = 2, @ErrMsg = 'Invalid invoice detail inputs.'
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
			SELECT @ErrCode = 0, @ErrMsg = 'Invoice saved successfully.', @NewInvoiceNumber = @InvoiceNumber
		END
		-- End Region
		
		-- Region: Write Log		
		
		-- End Region
	END
	ELSE
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'Invalid invoice header inputs.'
		RETURN
	END
END
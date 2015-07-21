USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceDetailInsert]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LA_Inv_InvoiceDetailInsert] 
	  @InvoiceHeaderId INT
	, @ItemName VARCHAR(200)
	, @Reference VARCHAR(100)
	, @ProductId INT
	, @FeeType TINYINT
	, @Amount MONEY
	, @ErrCode INT = 0 OUTPUT  
	, @ErrMsg VARCHAR(4000) = '' OUTPUT
WITH RECOMPILE
AS
SET NOCOUNT ON
BEGIN	
	INSERT INTO dbo.LA_InvoiceDetail
	(
	    --InvoiceDetailId - this column value is auto-generated
	    InvoiceHeaderId,
	    ItemName,
	    Reference,
	    ProductId,
	    FeeType,
	    Amount
	)
	VALUES
	(
	    @InvoiceHeaderId 
		, @ItemName
		, @Reference
		, @ProductId
		, @FeeType
		, @Amount
	)
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = 'Insert invoice detail failed.'
	END
END
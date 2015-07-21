USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceHeaderInsert]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LA_Inv_InvoiceHeaderInsert] 
	  @BillerId			INT
	, @PartyId INT`
	, @RefNo INT
	, @CurrencyId INT
	, @InvoiceKey VARCHAR(20)
	, @InvoiceNo INT
	, @InvoiceDate DATETIME
	, @DueDate DATETIME
	, @Amount MONEY
	, @InvoiceType SMALLINT
	, @StatusId SMALLINT
	, @Note VARCHAR(200)
	, @HasSent BIT
	, @HasDeleted BIT
	, @CreatedBy INT
	, @CreatedDateTime DATETIME
	, @UpdatedDateTime DATETIME
	, @InvoiceDetailXml VARCHAR(1000)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
WITH RECOMPILE
AS
SET NOCOUNT ON
/*  
	 Created: 20150721@Bravo
	 Task : Create Invoice 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:		
		+ @@InvoiceDetailXml: '<InvoiceDetails>
									<InvoiceDetail>
										<ProductId>0</ProductId>
										<InvoiceAmount>900.12</InvoiceAmount>
										<AmountType>0</AmountType>
									</InvoiceDetail>
									<InvoiceDetail>
										<ProductId>1</ProductId>
										<InvoiceAmount>90.01</InvoiceAmount>
										<AmountType>0</AmountType>
									</InvoiceDetail>
									<InvoiceDetail>
										<ProductId>2</ProductId>
										<InvoiceAmount>81.1</InvoiceAmount>
										<AmountType>2</AmountType>
									</InvoiceDetail>
								</InvoiceDetails>'
*/
BEGIN	
	
END
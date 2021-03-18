/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210317@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: AMF WriteOff AmountInEUR Then Initilize AmountInCNY
*/
USE bodb_Licensee 
GO

DECLARE @CutOffTime DATE = '20210301',
		@EUR_CurrencyId INT = 6, @CNY_CurrencyId INT = 13,
		@AMF_ItemTypeId INT = 3, @WriteOffAMF_ItemTypeId INT = 21,
		@Environment VARCHAR(50) = 'PRO'
		
DECLARE @AMF_TransferAmount	TABLE (PartyID INT, PartyName VARCHAR(50), FromAmount_InEUR MONEY,  ToAmount_InCNY MONEY) 

PRINT 'Prepare AMF transfer amount here: 5 records'
BEGIN
	INSERT INTO @AMF_TransferAmount(PartyId, PartyName, FromAmount_InEUR, ToAmount_InCNY)
	VALUES(368, 'A1game', 5000, 100000)
		 ,(72, '9Club', 40000, 80000)
END

PRINT 'Step 1. Write off'
BEGIN
	PRINT 'Step 1.1: Insert data into Invoice Table'

	
	PRINT 'Step 1.2: Update MonthOfDeduction = 0'
END

PRINT 'Step 2. Initilize CNY amount'
BEGIN
	PRINT 'Step 2.1: Insert data into Invoice Table'
		PRINT 'Step 2.1.1: Insert data into LA_InvoiceHeader'
		INSERT INTO dbo.LA_InvoiceHeader (BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,Amount,InvoiceType,StatusId,Note,Environment,FromDate,ToDate,DueDate,HasDeleted,HasSent,CreatedBy,CreatedDateTime)
		SELECT * 
		FROM 
		(
			VALUES(@BillerId, @ToPartyId, 0, '', 1, GETDATE(), @Amount, @InvoiceTypeId, 0, '', @Environment,GETDATE(),GETDATE(),GETDATE(),0,0,@UserId,GETDATE())
		)V(BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,Amount,InvoiceType,StatusId,Note,Environment,FromDate,ToDate,DueDate,HasDeleted,HasSent,CreatedBy,CreatedDateTime)

		PRINT 'Step 2.1.2: Insert data into LA_InvoiceStatement'


	PRINT 'Step 2.2: Update MonthOfDeduction = CEILING(@ToAmount_InCNY / LA_MinFee.FeeAmount)'
END
/*Note
1. Update MonthOfDeduction
 - SP: LA_Inv_InvoiceInfoInsert
 - Line 287
 - Write Off: MonthOfDeduction = 0
 - Initlize: 

2. 
*/
SELECT * FROM LA_InvoiceHeader WITH(NOLOCK) WHERE InvoiceHeaderId IN(4130, 4131)
SELECT * FROM LA_InvoiceStatement WITH(NOLOCK) WHERE InvoiceHeaderId = 4130
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
		@AMF_ItemTypeId INT = 3, @WriteOffAMF_ItemTypeId INT = 21, @InvoiceTypeId INT = 12,
		@Environment VARCHAR(50) = 'PRO'
DECLARE @PreviousCutOffTime DATE = DATEADD(DAY, -1, @CutOffTime)

DECLARE @AMF_TransferAmount	TABLE (PartyID INT, PartyName VARCHAR(50), FromAmount_InEUR MONEY,  ToAmount_InCNY MONEY) 
DECLARE @InvoiceHeaderInserted TABLE (InvoiceHeaderId INT, PartyId INT, IsWriteOff BIT)

PRINT 'Prepare AMF transfer amount here: 5 records'
BEGIN
	INSERT INTO @AMF_TransferAmount(PartyId, PartyName, FromAmount_InEUR, ToAmount_InCNY)
	VALUES(368, 'A1game', 5000, 100000)
		 ,(72, '9Club', 40000, 80000)
END

PRINT 'Step 1. Write off'
BEGIN
	PRINT 'Step 1.1: Insert data into Invoice Table'
		PRINT 'Step 1.1.1: Insert data into LA_InvoiceHeader'
			INSERT INTO dbo.LA_InvoiceHeader (BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,Amount,InvoiceType,StatusId,Note,Environment,FromDate,ToDate,DueDate,HasDeleted,HasSent,CreatedBy,CreatedDateTime)
			OUTPUT INSERTED.InvoiceHeaderId, INSERTED.PartyId, 1 INTO @InvoiceHeaderInserted(InvoiceHeaderId, PartyId, IsWriteOff)
			SELECT 0 AS BillerId,PartyID, @EUR_CurrencyId,'',1,@PreviousCutOffTime, FromAmount_InEUR, @InvoiceTypeId,0,'',@Environment,@PreviousCutOffTime,@PreviousCutOffTime,@PreviousCutOffTime,0,0,1,GETDATE()
			FROM @AMF_TransferAmount

		PRINT 'Step 1.1.2: Insert data into LA_InvoiceStatement'
			INSERT INTO dbo.LA_InvoiceStatement(InvoiceHeaderId, InvItemTypeId, RefPartyId, [Description], Income, Expense)
			SELECT i.InvoiceHeaderId, 21 /*Write off AMF*/, f.PartyID
				, N'Convert AMF from EUR to CNY' + CHAR(13) + 'From Amount: EUR ' + CONVERT(VARCHAR, f.FromAmount_InEUR, 1)+ CHAR(13) + 'To Amount: CNY ' + CONVERT(VARCHAR, f.ToAmount_InCNY, 1)
				, -f.FromAmount_InEUR
				, 0
			FROM @AMF_TransferAmount f
			INNER JOIN @InvoiceHeaderInserted i ON f.PartyID = i.PartyId
			WHERE i.IsWriteOff = 1
	PRINT 'Step 1.2: Update MonthOfDeduction = 0'
		UPDATE m SET MonthOfDeduction = 0
		FROM @AMF_TransferAmount f
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON f.PartyID = m.PartyId AND m.FeeTypeId = 1 --MinFee
												   AND m.CurrencyId = @EUR_CurrencyId
												   AND @PreviousCutOffTime BETWEEN m.FromDate AND m.ToDate
END

PRINT 'Step 2. Initilize CNY amount'
BEGIN
	PRINT 'Step 2.1: Insert data into Invoice Table'
		PRINT 'Step 2.1.1: Insert data into LA_InvoiceHeader'
			INSERT INTO dbo.LA_InvoiceHeader (BillerId,PartyId,CurrencyId,InvoiceSymbol,InvoiceNumber,InvoiceDate,Amount,InvoiceType,StatusId,Note,Environment,FromDate,ToDate,DueDate,HasDeleted,HasSent,CreatedBy,CreatedDateTime)
			OUTPUT INSERTED.InvoiceHeaderId, INSERTED.PartyId, 0 INTO @InvoiceHeaderInserted(InvoiceHeaderId, PartyId, IsWriteOff)
			SELECT 0 AS BillerId,PartyID,@CNY_CurrencyId,'',1,@CutOffTime, ToAmount_InCNY, @InvoiceTypeId,0,'',@Environment,@CutOffTime,@CutOffTime,@CutOffTime,0,0,1,GETDATE()
			FROM @AMF_TransferAmount

		PRINT 'Step 2.1.2: Insert data into LA_InvoiceStatement'
			INSERT INTO dbo.LA_InvoiceStatement(InvoiceHeaderId, InvItemTypeId, RefPartyId, [Description], Income, Expense)
			SELECT i.InvoiceHeaderId, 3 /*initialize AMF*/, f.PartyID
				, N'Convert AMF from EUR to CNY' + CHAR(13) + 'From Amount: EUR ' + CONVERT(VARCHAR, f.FromAmount_InEUR, 1)+ CHAR(13) + 'To Amount: CNY ' + CONVERT(VARCHAR, f.ToAmount_InCNY, 1)
				, f.ToAmount_InCNY
				, 0
			FROM @AMF_TransferAmount f
			INNER JOIN @InvoiceHeaderInserted i ON f.PartyID = i.PartyId 
			WHERE i.IsWriteOff = 0

	PRINT 'Step 2.2: Update MonthOfDeduction = CEILING(@ToAmount_InCNY / LA_MinFee.FeeAmount)'
		UPDATE m SET MonthOfDeduction = CEILING(f.ToAmount_InCNY / m.FeeAmount)
		FROM @AMF_TransferAmount f
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON f.PartyID = m.PartyId AND m.FeeTypeId = 1 --MinFee
												   AND m.CurrencyId = @CNY_CurrencyId
												   AND @CutOffTime BETWEEN m.FromDate AND m.ToDate
END
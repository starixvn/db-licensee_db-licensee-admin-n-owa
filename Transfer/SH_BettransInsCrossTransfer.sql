/*<info serverAlias="DBTXN-bodb02" executers="wsv_nap" viewers="vnteam" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_BettransInsCrossTransfer]
(
	@FromCustID		INT,
	@ToCustID		INT,
	@FromAmount		MONEY,
	@ToAmount		MONEY,
	@FromExRate		FLOAT,
	@ToExRate		FLOAT,
	@ForexUsername	NVARCHAR(50),
	@Remark			NVARCHAR(200),
	@UserID			INT, --custid of Admin
	@IP				VARCHAR(45)='',
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			NVARCHAR(200) = '' OUTPUT,
	@Language		VARCHAR(2)= 'E',
	@isCollection 	BIT = 0,
	@BUID			INT = NULL
)
AS
/*
	Created:20250701@Eddie
	DB: DBTXN/bodb02
	Task: Service Job ( Automate Finance Transfer for Licensees )
	Orig SP: Acc_BettransInsCrossTransfer

	Revisions:
		- 20250701@Eddie: Initialize SP [RedmineID: #231003]
*/
BEGIN
	SET NOCOUNT ON	
	
	--Check To account not the same From account 
	IF @FromCustID = @ToCustID 
	BEGIN
		SELECT @ErrMsg = 'You cannot do TRANSFER due to the destination account is the same as the source account.', @ErrCode = 100 
		RETURN
	END 
	

	---- #1 CHECK UM TRANSFER FUNCTION
	EXEC DBCUST.CUSTDB.dbo.Acc_Transfer_CheckUM  
		@CustID = @FromCustID
		,@Language = @Language
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- Function Transfer is under UM 
	BEGIN
		RETURN		
	END		
	
	EXEC DBCUST.CUSTDB.dbo.Acc_Transfer_CheckUM  
		@CustID = @ToCustID
		,@Language = @Language
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- Function Transfer is under UM 
	BEGIN
		RETURN		
	END		
			
	DECLARE @refno			BIGINT,
			@winlostdate	DATETIME, 
			@transdate		DATETIME,
			@RemarkFromCurr	NVARCHAR(70),
			@RemarkToCurr	NVARCHAR(70),
			@TransID		BIGINT

	DECLARE @TransIDs AS TABLE (transID BIGINT)	
	
	DECLARE @FromUsername	NVARCHAR(50),
			@FromCurrency	INT,
			@FromActualRate FLOAT,
			@FromCurrName	NVARCHAR(50),
			@FromRecommend	INT,
			@FromMrecommend	INT,
			@FromSrecommend	INT,
			@FromRoleID		TINYINT

	DECLARE @ToUsername		NVARCHAR(50),
			@ToCurrency		INT,
			@ToActualRate	FLOAT,
			@ToCurrName		NVARCHAR(50),
			@ToRecommend	INT,
			@ToMrecommend	INT,
			@ToSrecommend	INT,
			@ToRoleID		TINYINT

	DECLARE @ForexCustID 		INT,
			@ForexCurrency		INT,
			@ForexActualRate	FLOAT,
			@ForexCurrName		NVARCHAR(50),
			@ForexRecommend		INT,
			@ForexMrecommend	INT,
			@ForexSrecommend	INT

	--- Get @FromCustomer info 
	SELECT 
		@FromUsername	= c.username,
		@FromCurrency	= c.currency,
		@FromActualRate = e.actualrate,
		@FromCurrName	= e.currency,
		@FromRecommend	= c.recommend,
		@FromMrecommend	= c.mrecommend,
		@FromSrecommend	= c.srecommend,
		@FromRoleID		= c.roleid
	from CustDB.dbo.Custinfo c WITH(NOLOCK)
			INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
	WHERE c.custid = @FromCustID

	--- Get @ToCustomer info
	SELECT 
		@ToUsername		= c.username,
		@ToCurrency		= c.currency,
		@ToActualRate	= e.actualrate,
		@ToCurrName		= e.currency,
		@ToRecommend	= c.recommend,
		@ToMrecommend	= c.mrecommend,
		@ToSrecommend	= c.srecommend,
		@ToRoleID		= c.roleid
	from CustDB.dbo.Custinfo c WITH(NOLOCK)
			INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
	WHERE c.custid = @ToCustID	

	-- Get @ForexCustomer info
	SELECT 
		@ForexCustID	= c.custID,
		@ForexCurrency	= c.currency,
		@ForexActualRate= e.actualrate,

		@ForexCurrName	= e.currency,
		@ForexRecommend	= c.recommend,
		@ForexMrecommend= c.mrecommend,
		@ForexSrecommend= c.srecommend
	from CustDB.dbo.Custinfo c WITH(NOLOCK)
			INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
	WHERE c.username = @ForexUsername

	IF	@FromUsername IS NULL OR @FromUsername = '' OR
		@ToUsername IS NULL OR @ToUsername = '' OR 
		@ForexCustID IS NULL OR @ForexCustID = 0
	BEGIN
		SELECT @ErrMsg =CASE @Language 
							WHEN 'E' THEN 'Customer does not exist.'
							WHEN 'CS' THEN N'Customer does not exist.'
							WHEN 'J' THEN N'ID確認できません。'
							ELSE N'Customer does not exist.'
						END, @ErrCode = 101
		RETURN
	END

	IF @ToCurrency = @FromCurrency
	BEGIN
		SELECT @ErrMsg =CASE @Language 
							WHEN 'E' THEN 'This is not cross-currency transfer.'
							WHEN 'CS' THEN N'This is not cross-currency transfer.'
							WHEN 'J' THEN N'This is not cross-currency transfer.'
							ELSE N'This is not cross-currency transfer.'
						END, @ErrCode = 102
		RETURN
	END

	IF (@ToAmount/@FromAmount <= 0 OR @FromExRate <=0 OR @ToExRate <=0) AND @FromUsername NOT IN ('SPONSuperUUS','Athena000SuperUUS','SampleSiteSuperUUS')
	BEGIN	
		SELECT @ErrMsg =CASE @Language
							WHEN 'E' THEN 'Invalid amount or exchange rate.'
							WHEN 'CS' THEN N'Invalid amount or exchange rate.'
							WHEN 'J' THEN N'Invalid amount or exchange rate.'
							ELSE N'Invalid amount or exchange rate.'
						END, @ErrCode = 103	
		RETURN
	END
	
	SELECT	@transdate		= CURRENT_TIMESTAMP,
			@RemarkFromCurr	= '',  
			@RemarkToCurr	= '',
			@winlostdate = CONVERT(NVARCHAR(10), CURRENT_TIMESTAMP,120)

	EXEC Get_Refno_Transid @RefNo = @RefNo OUTPUT

	----- transfer from @FromCustomer to @ForexAcc
	
	SELECT	@RemarkFromCurr =   ' - ' +@FromCurrName + ' '+ CONVERT(NVARCHAR(50),@FromAmount),
			@RemarkToCurr   =   ' - ' +@ForexCurrName+ ' '+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),@FromAmount * @FromExRate))


	--- update @FromCustID's credit if this action reduce balance, then insert transfer transaction into bettrans
	--- whereas this action increase balance, insert bettrans first then update credit	
	DECLARE @tmp MONEY
	IF @FromAmount < 0 AND @FromRoleID = 1	
	BEGIN		
		SET @tmp = ABS(@FromAmount)
		EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @tmp, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
		IF @ErrCode <> 0
		BEGIN
			SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
											 WHEN 'CS' THEN N'Transfer failed. Please try again.'
											 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
											 ELSE N'Transfer failed. Please try again.'
							 END, 
					@ErrCode = 104									
			RETURN
		END
	END

	--- Insert Transfer
	EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
	INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
						 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
						 scomm, swinlost,ip,statusID, RepUpdateTime)
	OUTPUT INSERTED.TransID INTO @TransIDs
	VALUES(@TransID, @UserID, @FromCustID, @FromUsername, @refno, @transdate,21003, 'To Customer: ' + @ForexUsername + '('+ @Remark +')' + @RemarkToCurr, 
						CASE WHEN @FromAmount > 0 THEN @FromAmount ELSE 0 END , CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@FromAmount) END,
						@winlostdate, @FromCurrency, @FromActualRate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend,
						0, 0, @ip,131, SYSDATETIME())
	
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 104		
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME()
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)

		--- rollback credit
		IF @FromAmount < 0 AND @FromRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
		RETURN
	END
	
	--- Insert Transfer_Coll
		IF @IsCollection = 1
		INSERT INTO Transfer_Coll 
				( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, RepUpdateTime )
		SELECT 	CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, SYSDATETIME()
		FROM dbo.Transfer WITH (NOLOCK) 
		WHERE TransID = @TransID
	  
	
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 104		
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)

		--- rollback credit
		IF @FromAmount < 0 AND @FromRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2 
		RETURN
	END

	---Insert into Transfer_Info
	INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
	SELECT TransId, @isCollection, SYSDATETIME(), @BUID
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID

	if @@Error <> 0
	BEGIN
		Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 104	
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		--- rollback credit
		IF @FromAmount < 0 AND @FromRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
		RETURN

		return
	END		
	
	---- update @FromCustID's credit if this action increase balance
	IF @FromAmount > 0 AND @FromRoleID = 1	
	BEGIN
		EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @ErrCode = @ErrCode OUTPUT
		IF @ErrCode <> 0
		BEGIN
			Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 104	
				
			UPDATE dbo.Transfer WITH(ROWLOCK)
			SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
			WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003
	
			UPDATE Transfer_Coll WITH(ROWLOCK)
			SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
			WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
					AND refno = @refno 
					AND bettype = 21003

			UPDATE TransferInfo WITH(ROWLOCK)
			SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
			WHERE  TransID IN (SELECT TransID FROM @TransIDs)

			RETURN
		END
	END

	
	---- update Forex account's credit
	EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
	INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
						winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
						 scomm, swinlost,ip,statusID, RepUpdateTime)
	OUTPUT INSERTED.TransID INTO @TransIDs
	VALUES(@TransID, @UserID,@ForexCustID,@ForexUsername, @refno, @transdate,21003, 'From Customer: ' + @FromUsername + '('+ @Remark +')' + @RemarkFromCurr, 
						CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@FromAmount)*@FromExRate END, CASE WHEN @FromAmount > 0 THEN @FromAmount*@FromExRate ELSE 0 END,
						@winlostdate, @ForexCurrency, @ForexActualRate, @ForexCurrName, @ForexRecommend, @ForexMrecommend, @ForexSrecommend,
						0, 0, @ip,131, SYSDATETIME())
					
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 105

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
			
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1 	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
		RETURN
	END
	
	--- Insert Transfer_Coll
	IF @IsCollection = 1
	INSERT INTO Transfer_Coll 
			( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, RepUpdateTime )
	SELECT 	CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, SYSDATETIME()
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID  
	
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 105

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)

		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1 	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
		RETURN
	END

	---Insert into Transfer_Info
	INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
	SELECT TransId, @isCollection, SYSDATETIME(), @BUID
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID

	if @@Error <> 0
	BEGIN
		Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 105	
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2	
		RETURN
	END		

	----- transfer from @ForexAcc to @ToCustomer
	IF @FromAmount > 0
	BEGIN
		SELECT	@RemarkFromCurr =   ' - ' + @ForexCurrName	+ ' -'+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),@ToAmount* @ToExRate)),
				@RemarkToCurr   =   ' - ' +	@ToCurrName		+ ' -'+ CONVERT(NVARCHAR(50),@ToAmount )
	END	
	IF @FromAmount < 0
	BEGIN
		SELECT	@RemarkFromCurr =   ' - ' + @ForexCurrName	+ ' '+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),ABS(@ToAmount)* @ToExRate)),
				@RemarkToCurr   =   ' - ' +	@ToCurrName		+ ' '+ CONVERT(NVARCHAR(50),ABS(@ToAmount) )
	END
	
	EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
	INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
						 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
						 scomm, swinlost,ip,statusID, RepUpdateTime)
	OUTPUT INSERTED.TransID INTO @TransIDs
	VALUES(@TransID, @UserID,@ForexCustID,@ForexUsername, @refno, @transdate,21003, 'From Customer: ' + @ToUsername + '('+ @Remark +')' + @RemarkToCurr, 
						CASE WHEN @FromAmount > 0 THEN @ToAmount*@ToExRate ELSE 0 END, CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@ToAmount)*@ToExRate END,
						@winlostdate, @ForexCurrency, @ForexActualRate, @ForexCurrName, @ForexRecommend, @ForexMrecommend, @ForexSrecommend,
						0, 0, @ip,131, SYSDATETIME())
		
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 106

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2

		RETURN
	END
	
	
	--- Insert Transfer_Coll
	IF @IsCollection = 1
	INSERT INTO Transfer_Coll 
			( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, RepUpdateTime )
	SELECT 	CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, SYSDATETIME()
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID	 
	
	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 106

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2

		RETURN
	END

	---Insert into Transfer_Info
	INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
	SELECT TransId, @isCollection, SYSDATETIME(), @BUID
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID

	IF @@Error <> 0
	BEGIN
		Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 106		
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2

		RETURN
	END		
	
	
	--- update @ToCustID's credit if this action reduce balance, then insert transfer transaction into bettrans
	--- whereas this action increase balance, insert bettrans first then update credit
	IF @FromAmount > 0 AND @ToRoleID = 1		
		EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT --EXEC Dot_BalanceUpdDebit @CustID = @ToCustID, @balance = @ToAmount
	IF @ErrCode <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 107

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
	
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2		
		RETURN
	END
	
	EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
	INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
						 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
						 scomm, swinlost,ip,statusID, RepUpdateTime)
	OUTPUT INSERTED.TransID INTO @TransIDs	
	VALUES(@TransID, @UserID, @ToCustID, @ToUsername, @refno, @transdate,21003, 'To Customer: ' + @ForexUsername + '('+ @Remark +')' + @RemarkFromCurr, 
						CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@ToAmount) END, CASE WHEN @FromAmount > 0 THEN ABS(@ToAmount) ELSE 0 END,
						@winlostdate, @ToCurrency, @ToActualRate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend,
						0, 0, @ip,131, SYSDATETIME())

	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 107

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
	
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2	

		IF @FromAmount > 0 AND @ToRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2
		RETURN
	END
	
	--- Insert Transfer_Coll
	IF @IsCollection = 1
	INSERT INTO Transfer_Coll 
			( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, RepUpdateTime )
	SELECT 	CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
			TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
			Creator ,TransDesc, IP, SYSDATETIME()
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID	 

	IF @@ERROR <> 0
	BEGIN
		SELECT  @ErrMsg = CASE @Language WHEN 'E'  THEN 'Transfer failed. Please try again.'
										 WHEN 'CS' THEN N'Transfer failed. Please try again.'
										 WHEN 'J'  THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
										 ELSE N'Transfer failed. Please try again.'
						 END, 
				@ErrCode = 107

		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
	
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2

		IF @FromAmount > 0 AND @ToRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2 
		RETURN
	END
	
	---Insert into Transfer_Info
	INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
	SELECT TransId, @isCollection, SYSDATETIME(), @BUID
	FROM dbo.Transfer WITH (NOLOCK) 
	WHERE TransID = @TransID

	if @@Error <> 0
	BEGIN
		Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 107		
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
			AND refno = @refno 
			AND bettype = 21003
	
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)
		
		IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
		IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2 

		IF @FromAmount > 0 AND @ToRoleID = 1
			EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2

		RETURN
	END		
	
	DECLARE @amtTo MONEY

	IF @FromAmount < 0 AND @ToRoleID = 1
	BEGIN
		SET @amtTo = ABS(@ToAmount)
		EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @amtTo, @type = 2, @ErrCode = @ErrCode OUTPUT

		IF @ErrCode <> 0
		BEGIN
			Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 107		
				
			UPDATE dbo.Transfer WITH(ROWLOCK)
			SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
			WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
				AND refno = @refno 
				AND bettype = 21003
	
			UPDATE Transfer_Coll WITH(ROWLOCK)
			SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
			WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
					AND refno = @refno 
					AND bettype = 21003

			UPDATE TransferInfo WITH(ROWLOCK)
			SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
			WHERE  TransID IN (SELECT TransID FROM @TransIDs)

			IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
				EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
			IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
				EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2 

			RETURN
		END
	END	
	
	DECLARE @SystemExRate	FLOAT,
			@TransExRate	FLOAT,
			@LogData		VARCHAR(1000)

	SELECT	@SystemExRate = ROUND(@FromExRate/@ToExRate,4),
			@TransExRate  = ROUND(@ToAmount/@FromAmount,4)


	SELECT @LogData = 'Transfer from Customer ' + @FromUserName + ' to Customer ' + @ToUserName + 
					  ' with from amount ' + CONVERT(VARCHAR(20), @FromAmount) + ' to amount ' + CONVERT(VARCHAR(20), @ToAmount) +
					  ' (System Ex.Rate' + '(' + @FromCurrName + '/' + @ToCurrName + ') ' + CONVERT(VARCHAR(20),@SystemExRate) + 
					  ' Trans Ex.Rate' + '(' + @FromCurrName + '/' + @ToCurrName + ') ' + CONVERT(VARCHAR(20),@TransExRate) + ')' + 
					  ' Ref.No ' + CONVERT(VARCHAR(20), @refno)

	IF @IsCollection = 1 
	BEGIN 
		SELECT @LogData = @LogData + ' is Credit Collection'
	END

	
	EXEC DBCTG.bodb02.dbo.Acc_ExchangeRateCheckValid 
			@FromExchangeID = @FromCurrency, 
			@ToExchangeID	= @ToCurrency, 
			@ExchangeRate	= @TransExRate,
			@UserID			= @UserID , 
			@FromCust		= @FromCustID, 
			@ToCust			= @ToCustID, 
			@Amount			= @FromAmount, 
			@transDate		= @transdate ,
			@refNo			= @refno,
			@ErrCode = @ErrCode OUTPUT,
			@ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0
	BEGIN 
		SELECT @ErrMsg = CASE @Language 
					WHEN 'E' THEN 'Transfer failed. Please try again.'
					WHEN 'CS' THEN N'Transfer failed. Please try again.'
					WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					ELSE N'Transfer failed. Please try again.'
				END, @ErrCode = 107		
				
			UPDATE dbo.Transfer WITH(ROWLOCK)
			SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
			WHERE custid IN (@FromCustID, @ToCustID, @ForexCustID)
				AND TransID IN (SELECT TransID FROM @TransIDs)
				AND bettype = 21003
				
			UPDATE Transfer_Coll WITH(ROWLOCK)
			SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
			WHERE	custid in (@FromCustID, @ToCustID, @ForexCustID)
					AND TransID IN (SELECT TransID FROM @TransIDs)
					AND bettype = 21003

			UPDATE TransferInfo WITH(ROWLOCK)
			SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
			WHERE  TransID IN (SELECT TransID FROM @TransIDs)
			
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	--- rollback for add to credit
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1	
				IF @FromAmount < 0 AND @FromRoleID = 1	--- rollback for add to debit
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2 

				IF @FromAmount > 0 AND @ToRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2
				IF @FromAmount < 0 AND @ToRoleID = 1
					EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @amtTo, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
			END
			RETURN
	END 

	BEGIN TRY
		EXEC DBLOG.bodb_customerlog.dbo.WriteLog_UserLog_Transfer @UserID = @UserID, @FromCustID = @FromCustID, @ToCustID = @ToCustID, @IP = @IP, @Doing = @LogData
	END TRY
	BEGIN CATCH
		Select @LogData = @LogData + ' ErrMsg=' + error_message()
		EXEC bodb_customerlog.dbo.WriteLog_UserLog_Transfer @UserID = @UserID, @FromCustID = @FromCustID, @ToCustID = @ToCustID, @IP = @IP, @Doing = @LogData
	END CATCH
END

GO
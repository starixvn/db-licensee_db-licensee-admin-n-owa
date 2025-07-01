/*<info serverAlias="DBTXN-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_BettransInsTransfer]
	@FromCustID int,
	@ToUserName varchar(30), 
	@Amount money,
	@ExchangeRate float,
	@Remark nvarchar(200),
	@UserID int, --custid of Admin
	@IP varchar(45)='',
	@ErrCode int = 0 OUTPUT,
	@ErrMsg nvarchar(200) = '' OUTPUT,
	@Language varchar(2)= 'E',
	@isCollection BIT = 0,
	@BUID INT = NULL
AS
/*
	Created:20250701@Eddie
	Task: Service Job ( Automate Finance Transfer for Licensees )
	DB: DBTXN/bodb02
	Orig SP: Acc_BettransInsTransfer
	
	Revisions:
		- 20250701@Eddie: Initialize SP [RedmineID: #231003]
					   
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON


	Declare @ToMrecommend int, @ToRecommend int, @ToSrecommend int, @ToCustID int, @Amt money,
			@ToCurr int, @ToActualrate float, @ToCurrName nvarchar(10), @RemarkFromCurr nvarchar(70), @RemarkToCurr nvarchar(70), @ToRoleID tinyint, @ToCurrCode VARCHAR(12)
	Declare @FromMrecommend int, @FromRecommend int, @FromSrecommend int, 
			@FromCurr int, @FromActualrate float , @FromCurrName nvarchar(10),@FromUsername varchar(30), @FromRoleID tinyint, @FromCurrCode VARCHAR(12)
	Declare @LogData varchar(200) 
	
	
	---- #1 CHECK UM TRANSFER FUNCTION
	EXEC DBCUST.CUSTDB.dbo.Acc_Transfer_CheckUM  
		@CustID = @FromCustID
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- Function Transfer is under UM 
	BEGIN
		RETURN		
	END		
	
	---- #2 CHECK FLAG ISTRANSFERRING = 1 THEN RAISE ERROR, IF THIS SP IS CALLED BY JOB THEN NO NEED TO CHECK  
	EXEC DBCUST.CUSTDB.dbo.Acc_Transfer_CheckRunningByCust  
		@CustID = @FromCustID
		,@Language = @Language
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- the auto transfer job is running this custid
	BEGIN
		RETURN		
	END
	
	-----------------------------------------------------------
	DECLARE @TransIDs AS TABLE (transID BIGINT)	

	Declare @refno bigint, @winlostdate datetime, @transdate datetime, @BalanceAmount MONEY, @TransID BIGINT

	select  @RemarkFromCurr='',  @RemarkToCurr=''
	select @Amt = @Amount 
	select @transdate = current_timestamp 	
	select @winlostdate = convert(nvarchar(10), current_timestamp,120)

	select @FromUsername = c.username, 
		@FromCurr = c.currency,
		@FromCurrName = e.currency,
		@FromRecommend = c.recommend,
		@FromMrecommend = c.mrecommend,
		@FromSrecommend = c.srecommend,
		@FromActualrate = e.actualrate,
		@FromRoleID = c.roleid,
		@FromCurrCode = e.Code
	from CustDB.dbo.Custinfo c with (NOLOCK)
		INNER JOIN CustDB.dbo.Exchange e with (NOLOCK) on c.currency = e.exchangeid 
	where c.CustID = @FromCustID


	Select @ToCustID = null
	select @ToCustID = c.CustID,
		   @ToCurr = c.currency,
		   @ToCurrName = e.currency,
		   @ToRecommend = c.recommend,
		   @ToMrecommend = c.mrecommend,
		   @ToSrecommend = c.srecommend,
		   @ToActualrate = actualrate,
		   @ToRoleID = c.roleid,
		   @ToCurrCode = e.Code
	from CustDB.dbo.Custinfo c with (NOLOCK)
		INNER JOIN CustDB.dbo.Exchange e with (NOLOCK) ON c.currency = e.exchangeid 
	where c.username = @ToUserName

	
	if @ToCustID is NULL or @ToCustID = 0
	BEGIN
		Select @ErrMsg = case @Language 
								when 'E' then 'Customer ' + @ToUserName + ' does not exist.'
								when 'CS' then N'Customer ' + @ToUserName + ' does not exist.'
								when 'J' then N'ID確認できません。'
								else N'Customer ' + @ToUserName + ' does not exist.'
						end, @ErrCode = 100
		return
	END
	
	---check To account not the same From account 
	IF @FromCustID = @ToCustID 
	BEGIN
		SELECT @ErrMsg = 'You cannot do TRANSFER due to the destination account is the same as the source account.', @ErrCode = 101
		RETURN
	END

	IF ( @FromCurrCode <> 'MYR' AND @ToCurrCode <> 'MYR' AND @FromCurrCode <> @ToCurrCode )
	BEGIN
		Select @ErrMsg = N'The two accounts have different currency code, but neither of them includes the RM currency. Please check again Users Info.'
			, @ErrCode = 104
		return
	END

	if not exists (select 1 from CustDB.dbo.Custinfo with (NOLOCK) where custid = @FromCustID)
	BEGIN
		Select @ErrMsg = case @Language 
								when 'E' then 'Customer does not exist.'
								when 'CS' then N'Customer does not exist.'
								when 'J' then N'ID確認できません。'
								else N'Customer does not exist.'
							end, @ErrCode = 102	
		return
	END
	
	---- #3 CHECK UM TRANSFER FUNCTION
	EXEC DBCUST.CustDB.dbo.Acc_Transfer_CheckUM  
		@CustID = @ToCustID
		,@Language = @Language
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- Function Transfer is under UM 
	BEGIN
		RETURN		
	END		
	
	---- #4 CHECK FLAG ISTRANSFERRING = 1 THEN RAISE ERROR, IF THIS SP IS CALLED BY JOB THEN NO NEED TO CHECK  
	EXEC DBCUST.CustDB.dbo.Acc_Transfer_CheckRunningByCust  
		@CustID = @ToCustID
		,@Language = @Language
		,@ErrMsg = @ErrMsg OUTPUT 
		,@ErrCode = @ErrCode OUTPUT
		 
	IF @ErrCode <> 0  -- the auto transfer job is running this custid
	BEGIN
		RETURN		
	END	


	/*
	--end
	--Check disable user
	EXEC DB052.bodb02.dbo.Acc_CustomerSelCheckEnable @custid = @FromCustID, @ErrCode=@ErrCode output,@ErrMsg=@ErrMsg output
	if @ErrCode <>0 return

	EXEC DB052.bodb02.dbo.Acc_CustomerSelCheckEnable @custid = @ToCustID, @ErrCode=@ErrCode output,@ErrMsg=@ErrMsg output
	if @ErrCode <>0 return
	--end
	*/
	if @Amount = 0 or @ExchangeRate = 0 
	BEGIN
		SELECT @ErrMsg =  case @Language
							when 'E' then 'Invalid amount or exchange rate.'
							when 'CS' then N'Invalid amount or exchange rate.'
							when 'J' then N'Invalid amount or exchange rate.'
							else N'Invalid amount or exchange rate.'
						end, @ErrCode = 107	
		return
	END

	-- get custID will be captured balance
	DECLARE @IsCaptureDownline BIT = 0
	DECLARE @CustIDCapture INT = 0
	
	IF @FromRoleID > @ToRoleID 
	BEGIN
		SELECT @CustIDCapture =  CASE	WHEN @ToRoleID = 1 AND  @ToRecommend = @FromCustID THEN @ToCustID
										WHEN @ToRoleID = 2 AND  @ToMrecommend = @FromCustID THEN @ToCustID
										WHEN @ToRoleID = 3 AND  @ToSrecommend = @FromCustID THEN @ToCustID 
										WHEN @ToRoleID = 1 AND	@FromRoleID = 4 AND @ToRecommend = -4 THEN @ToCustID
										WHEN @ToRoleID = 1 AND	@FromRoleID = 3 AND @ToRecommend = -3 THEN @ToCustID
								END
	END


	IF @ToRoleID > @FromRoleID 
	BEGIN
		SELECT @CustIDCapture =  CASE	WHEN @FromRoleID = 1 AND  @FromRecommend = @ToCustID THEN @FromCustID
										WHEN @FromRoleID = 2 AND  @FromMrecommend = @ToCustID THEN @FromCustID
										WHEN @FromRoleID = 3 AND  @FromSrecommend = @ToCustID THEN @FromCustID 
										WHEN @FromRoleID = 1 AND @FromSrecommend = @ToCustID AND @FromRecommend = -4 THEN @FromCustID
										WHEN @FromRoleID = 1 AND @FromMrecommend = @ToCustID AND @FromRecommend = -3 THEN @FromCustID
								END
	END
	

	IF @ExchangeRate <> 1 
	BEGIN
		SELECT @RemarkFromCurr =   ' - ' +@FromCurrName + ' '+ convert(nvarchar(50),@Amount)
		SELECT @RemarkToCurr   =   ' - ' +@ToCurrName   + ' '+ convert(nvarchar(50),CONVERT(NUMERIC(20,4),@amount * @ExchangeRate))
		
	END 

	EXEC Get_Refno_Transid @RefNo = @RefNo OUTPUT

		IF @amount > 0
		BEGIN
			---Insert into Transfer
			DECLARE @TotalCash MONEY = NULL
			IF @CustIDCapture = @FromCustID
			BEGIN
				EXEC Acc_CustomerSelCash_CaptureBalance @custid = @FromCustID, @TotalCash  = @TotalCash OUTPUT
			END

			EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
		   	INSERT INTO dbo.Transfer 
				(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
				winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
				 scomm, swinlost,ip,statusID, balance, RepUpdateTime)
			OUTPUT INSERTED.TransID INTO @TransIDs
			VALUES (@TransID, @UserID, @FromCustID, @FromUsername, @refno, @Transdate, 21003, 'To Customer: ' + @ToUserName + '('+ @Remark +')' + @RemarkToCurr, @amount, 0, 
				  @winlostdate, @FromCurr, @FromActualrate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend, 
				 0, 0,@ip,131, @TotalCash, SYSDATETIME())
								
			IF @@Error <> 0
			BEGIN
				Select @ErrMsg = case @Language 
							when 'E' then 'Transfer failed. Please try again.'
							when 'CS' then N'Transfer failed. Please try again.'
							when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							else N'Transfer failed. Please try again.'
						end, @ErrCode = 103		
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
				RETURN
			END		

			---Insert into Transfer_Coll
			IF @IsCollection = 1 
			INSERT INTO Transfer_Coll 
				( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, RepUpdateTime )
			SELECT CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, SYSDATETIME()
			FROM dbo.Transfer WITH (NOLOCK) 
			WHERE TransID = @TransID
						
			IF @@Error <> 0
			BEGIN
				Select @ErrMsg = case @Language 
							when 'E' then 'Transfer failed. Please try again.'
							when 'CS' then N'Transfer failed. Please try again.'
							when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							else N'Transfer failed. Please try again.'
						end, @ErrCode = 103		
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
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
						end, @ErrCode = 103		
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
				RETURN
			END		

			--- update balance credit for @FromCustID
			IF @FromRoleID  = 1
			BEGIN
				EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2,@errCode = @ErrCode OUTPUT
				IF @ErrCode <> 0
				BEGIN
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
					WHERE custid IN (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND refno = @refno 
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
					RETURN
				END
			END 
			-------------------------------------------

			--- update balance Debit for @ToCustID
			IF @ToRoleID  = 1
			BEGIN
				SELECT @BalanceAmount = @amount * @ExchangeRate
				EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2, @IsForced = 1, @ErrCode = @ErrCode OUTPUT
				IF @ErrCode <> 0
				BEGIN
					Select @ErrMsg = case @Language 
								when 'E' then 'Transfer failed. Please try again.'
								when 'CS' then N'Transfer failed. Please try again.'
								when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								else N'Transfer failed. Please try again.'
							end, @ErrCode = 104
					--- rollback @FromCustID
					IF @FromRoleID  = 1
					BEGIN
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1
					END 

					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
					WHERE custid IN (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND refno = @refno 
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE  TransID IN (SELECT TransID FROM @TransIDs)
				
					RETURN
				END
			END
			
			--- Inseret into Transfer
			DECLARE @TotalCash1 MONEY = NULL
			IF @CustIDCapture = @ToCustID
			BEGIN
				EXEC Acc_CustomerSelCash_CaptureBalance @custid = @ToCustID, @TotalCash  = @TotalCash1 OUTPUT
			END

			EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT

			INSERT INTO dbo.Transfer 
				(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
				 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
				 scomm, swinlost,ip,statusID, balance, RepUpdateTime)
			OUTPUT INSERTED.TransID INTO @TransIDs
			VALUES (@TransID, @UserID, @ToCustID, @ToUsername, @refno, @Transdate, 21003, 'From Customer: ' + @FromUserName + '('+ @Remark +')' + @RemarkFromCurr, 0, @amount * @ExchangeRate, 
				 @winlostdate, @ToCurr, @ToActualrate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend, 
				 0, 0,@ip,131, @TotalCash1, SYSDATETIME())
				 
				 
			IF @@Error <> 0
			BEGIN
				Select @ErrMsg = case @Language 
							when 'E' then 'Transfer failed. Please try again.'
							when 'CS' then N'Transfer failed. Please try again.'
							when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							else N'Transfer failed. Please try again.'
						end, @ErrCode = 104
				--- rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1
				END 

				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)

				--- rollback @ToCustID
				IF @ToRoleID  = 1
				BEGIN
					SELECT @BalanceAmount = @amount * @ExchangeRate
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2
				END
				
				RETURN
			END	

			---Insert into Transfer_Coll
			IF @IsCollection = 1 
			INSERT INTO Transfer_Coll 
				( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, RepUpdateTime )
			SELECT CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, SYSDATETIME()
			FROM dbo.Transfer WITH (NOLOCK) 
			WHERE TransID = @TransID
						
			if @@Error <> 0
			BEGIN
				Select @ErrMsg = case @Language 
							when 'E' then 'Transfer failed. Please try again.'
							when 'CS' then N'Transfer failed. Please try again.'
							when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							else N'Transfer failed. Please try again.'
						end, @ErrCode = 103	
						
				--- rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1
				END 
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
				--- rollback @ToCustID
				IF @ToRoleID  = 1
				BEGIN
					SELECT @BalanceAmount = @amount * @ExchangeRate
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2
				END
					
				return
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
						end, @ErrCode = 103		

				--- rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1
				END 
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)

				--- rollback @ToCustID
				IF @ToRoleID  = 1
				BEGIN
					SELECT @BalanceAmount = @amount * @ExchangeRate
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2
				END
					
				RETURN
			END		
		
			Select @LogData = 'Transfer from Customer ' + @FromUserName + ' to Customer ' + @ToUserName + ' with amount ' + convert(varchar(20), @Amt, 2) + ' Ref.No ' + convert(varchar(20), @refno)
			
		END
		ELSE
		BEGIN
			SET @amount = abs(@amount)
		
			----update balance Debit
			IF @FromRoleID  = 1
			BEGIN
				EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1, @ErrCode = @ErrCode OUTPUT
				IF @ErrCode <> 0
				BEGIN
					Select @ErrMsg = case @Language 
								when 'E' then 'Transfer failed. Please try again.'
								when 'CS' then N'Transfer failed. Please try again.'
								when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								else N'Transfer failed. Please try again.'
							end, @ErrCode = 105					

					RETURN
				END
			END
			
			DECLARE @TotalCash2 MONEY = NULL

			IF @CustIDCapture = @FromCustID
			BEGIN
				EXEC Acc_CustomerSelCash_CaptureBalance @custid = @FromCustID, @TotalCash  = @TotalCash2 OUTPUT
			END

			EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
			INSERT INTO dbo.Transfer 
				(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
				 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
				 scomm, swinlost,ip,statusID, balance, RepUpdateTime)
			OUTPUT INSERTED.TransID INTO @TransIDs
			VALUES (@TransID, @UserID, @FromCustID, @FromUsername, @refno, @Transdate, 21003, 'To Customer: ' + @ToUserName + '('+ @Remark +')'+@RemarkToCurr, 0, @amount, 
				  @winlostdate, @FromCurr, @FromActualrate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend, 
				 0, 0,@ip,131, @TotalCash2, SYSDATETIME())
			
			IF @@Error <> 0
			BEGIN
				Select @ErrMsg = case @Language 
							when 'E' then 'Transfer failed. Please try again.'
							when 'CS' then N'Transfer failed. Please try again.'
							when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							else N'Transfer failed. Please try again.'
						end, @ErrCode = 105
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
				SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END

				RETURN
			END
			
			---Insert into Transfer_Coll
			IF @IsCollection = 1
			INSERT INTO Transfer_Coll 
				( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, RepUpdateTime )
			SELECT CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, SYSDATETIME()
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
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)

				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END
					
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
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)

				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END
					
				RETURN
			END		

			--------------------------------------------------------------
			DECLARE @TotalCash3 MONEY = NULL

			IF @CustIDCapture = @ToCustID
			BEGIN
				EXEC Acc_CustomerSelCash_CaptureBalance @custid = @ToCustID, @TotalCash  = @TotalCash3 OUTPUT
			END
			EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
			INSERT INTO dbo.Transfer 
				(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
				 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
				 scomm, swinlost,ip,statusID, balance, RepUpdateTime)
			OUTPUT INSERTED.TransID INTO @TransIDs
			VALUES (@TransID, @UserID, @ToCustID, @ToUsername, @refno, @Transdate, 21003, 'From Customer: ' + @FromUserName + '('+ @Remark +')' + @RemarkFromCurr, @amount * @ExchangeRate, 0, 
				 @winlostdate, @ToCurr, @ToActualrate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend, 
				 0, 0,@ip,131, @TotalCash3, SYSDATETIME())
						
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
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
					
				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END

				RETURN
			END
			
			---Insert into Transfer_Coll
			IF @IsCollection = 1
			INSERT INTO Transfer_Coll 
				( CustId, WinlostDate, TransDate, Bettype, Debit, Credit, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, RepUpdateTime )
			SELECT CustId, WinlostDate, TransDate, Bettype, Actual_Stake, Winlost, Currency, ActualRate, 
				TransID, RefNo, Username, Recommend, MRecommend, SRecommend, 
				Creator ,TransDesc, IP, SYSDATETIME()
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
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)

				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END
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
				WHERE custid IN (@FromCustID, @ToCustID)
					AND refno = @refno 
					AND bettype = 21003
				
				UPDATE Transfer_Coll WITH(ROWLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE	custid in (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003

				UPDATE TransferInfo WITH(ROWLOCK)
				SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT TransID FROM @TransIDs)
				
				---rollback @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
				END

				RETURN
			END		

			----update balance Credit
			IF @ToRoleID  = 1
			BEGIN
				SELECT @BalanceAmount = @amount * @ExchangeRate 
				EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2, @ErrCode = @ErrCode OUTPUT

				IF @ErrCode <> 0
				BEGIN
					Select @ErrMsg = case @Language 
								when 'E' then 'Transfer failed. Please try again.'
								when 'CS' then N'Transfer failed. Please try again.'
								when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								else N'Transfer failed. Please try again.'
							end, @ErrCode = 106	
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
					WHERE custid IN (@FromCustID, @ToCustID)
						AND refno = @refno 
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND refno = @refno 
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE  TransID IN (SELECT TransID FROM @TransIDs)
				
					---rollback @FromCustID
					IF @FromRoleID  = 1
					BEGIN
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2
					END

					RETURN
				END		
			END
					
			Select @LogData = 'Transfer from Customer ' + @ToUserName + ' to Customer ' + @FromUserName + ' with amount ' + convert(varchar(20), @Amt, 2) + ' Ref.No ' + convert(varchar(20), @refno)
			
		END
		
	IF @IsCollection = 1 
	BEGIN 
		SELECT @LogData = @LogData + ' is Credit Collection'
	END
	-- reset yesterday balance for live casino	(only transfer on the same line)			
	IF (@FromRoleID  = 1 AND @ToCustID IN (@FromRecommend, @FromMrecommend, @FromSrecommend)) OR 
		(@ToRoleID  = 1 AND @FromCustID IN (@ToRecommend, @ToMrecommend, @ToSrecommend))
	BEGIN	
		DECLARE @isResetYesterdayBalance BIT, @ErrCode_ResetYesterdayBalance BIT, @YesterdayBalance MONEY
		
		IF @FromRoleID = 1		
									EXEC Acc_BalanceGameResetYesterday @CustID = @FromCustID, @isResetYesterdayBalance = @isResetYesterdayBalance OUTPUT, @YesterdayBalance = @YesterdayBalance	 OUTPUT, @ErrCode = @ErrCode_ResetYesterdayBalance OUTPUT	
		ELSE		
									EXEC Acc_BalanceGameResetYesterday @CustID = @ToCustID, @isResetYesterdayBalance = @isResetYesterdayBalance OUTPUT, @YesterdayBalance = @YesterdayBalance	 OUTPUT, @ErrCode = @ErrCode_ResetYesterdayBalance OUTPUT	
			
		Select @LogData = @LogData + CASE WHEN @isResetYesterdayBalance = 1 THEN 
											CASE WHEN @ErrCode_ResetYesterdayBalance = 0 THEN '. (ResetGameBalance = suscess, YesterdayBalance =' + CAST(@YesterdayBalance AS VARCHAR(50)) + ')' 
											ELSE '. (ResetGameBalance = fail)' END		
									ELSE '' END			
	END

	
	EXEC DBCTG.bodb02.dbo.Acc_ExchangeRateCheckValid 
		@FromExchangeID = @FromCurr, 
		@ToExchangeID = @ToCurr, 
		@ExchangeRate = @ExchangeRate,
		@UserID = @UserID , 
		@FromCust = @FromCustID, 
		@ToCust = @ToCustID, 
		@Amount = @Amt, 
		@transDate =@transdate ,
		@refNo = @refno,
		@ErrCode = @ErrCode OUTPUT,
		@ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0
	BEGIN 
		Select @ErrMsg = case @Language 
					when 'E' then 'Transfer failed. Please try again.'
					when 'CS' then N'Transfer failed. Please try again.'
					when 'J' then N'払戻処理上にエラーが発生しました。もう一度確認してください。'
					else N'Transfer failed. Please try again.'
				end, @ErrCode = 106	
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0		
		WHERE custid IN (@FromCustID, @ToCustID)
			AND refno = @refno 
			AND bettype = 21003
				
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID)
				AND refno = @refno 
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE  TransID IN (SELECT TransID FROM @TransIDs)

		IF @Amt > 0
		BEGIN
			IF @FromRoleID = 1
				EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @Type = 2, @IsForced = 1, @ErrCode = @ErrCode OUTPUT
			IF @ToRoleID = 1
				EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2
		END

		IF @Amt < 0
		BEGIN
			IF @FromRoleID = 1
				EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @Type = 2

			IF @ToRoleID = 1
				EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @BalanceAmount, @Type = 2, @IsForced = 1, @ErrCode = @ErrCode OUTPUT
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

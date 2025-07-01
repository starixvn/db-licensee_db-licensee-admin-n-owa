/*<info serverAlias="DBTXN-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SiteDB_SH_FinanceTransferBettransIns]
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
	@IsCollection BIT = 0,
	@refno			BIGINT	= NULL OUTPUT,
	@SiteDBGroupID	SMALLINT,
	@BUID			INT = NULL
AS
/*
	Created: 20250701@Eddie
	DB: DBTXN/BODB02
	Task: Automate Transfer for upload payment
	Orig SP: Acc_FinanceTransferBettransIns >>> SiteDB_Acc_FinanceTransferBettransIns

	Revisions:
		- 20250701@Eddie: Initialize SP [RedmineID: #231003]

	Param's Explanation:

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ToMrecommend INT, @ToRecommend INT, @ToSrecommend INT, @ToCustID INT, @Amt money, @ToRoleID TINYINT,
			@ToCurr INT, @ToActualrate FLOAT, @ToCurrName NVARCHAR(10), @RemarkFromCurr NVARCHAR(70), @RemarkToCurr NVARCHAR(70)
	DECLARE @FromMrecommend INT, @FromRecommend INT, @FromSrecommend INT, @FromRoleID TINYINT,
			@FromCurr INT, @FromActualrate FLOAT , @FromCurrName NVARCHAR(10),@FromUsername VARCHAR(30)
	DECLARE @LogData VARCHAR(200), @winlostdate DATETIME, @transdate DATETIME, @BalanceAmount MONEY, @TransID BIGINT 

	DECLARE @CustInfo TABLE (Username NVARCHAR(50), currency INT, CurrName NVARCHAR(10), recommend INT, mrecommend INT, srecommend INT, CustID INT, actualrate FLOAT, roleid TINYINT)
			
	DECLARE @SiteGroupInfo TABLE(SiteDBGroupID SMALLINT, LinkedServerName  VARCHAR(512), ClientAccessName VARCHAR(512), AGIP VARCHAR (50))
	DECLARE @FromSiteDBGroupID SMALLINT, @ToSiteDBGroupID SMALLINT

	SELECT @RemarkFromCurr='',  @RemarkToCurr=''
	SELECT @Amt = @Amount 
	SELECT @transdate   = CURRENT_TIMESTAMP 	
	SELECT @winlostdate = CONVERT(nvarchar(10), CURRENT_TIMESTAMP,120)

	DECLARE @TransIDs AS TABLE (transID BIGINT)

	INSERT INTO @CustInfo (username, currency, CurrName, recommend, mrecommend, srecommend, CustID, actualrate, roleid)
	SELECT	c.username, 
			c.currency,
			e.currency AS CurrName,
			c.recommend,
			c.mrecommend,
			c.srecommend,
			c.CustID,
			e.actualrate,
			c.roleid
	FROM CustDB.dbo.Custinfo c with (NOLOCK)
		INNER JOIN CustDB.dbo.Exchange e with (NOLOCK) on c.currency = e.exchangeid 
	WHERE c.CustID = @FromCustID  OR c.username = @ToUserName

	SELECT @FromUsername = c.username, 
		@FromCurr = c.currency,
		@FromCurrName = c.CurrName,
		@FromRecommend = c.recommend,
		@FromMrecommend = c.mrecommend,
		@FromSrecommend = c.srecommend,
		@FromActualrate = c.actualrate,
		@FromRoleID	= roleid
	FROM @CustInfo c
	WHERE c.CustID = @FromCustID

	SELECT @ToCustID = null
	SELECT @ToCustID = c.CustID,
		   @ToCurr = c.currency,
		   @ToCurrName = c.CurrName,
		   @ToRecommend = c.recommend,
		   @ToMrecommend = c.mrecommend,
		   @ToSrecommend = c.srecommend,
		   @ToActualrate = actualrate,
		   @ToRoleID	= roleid
	FROM @CustInfo c
	WHERE c.username = @ToUserName

	IF @ToCustID is NULL or @ToCustID = 0
	BEGIN
		SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Customer ' + @ToUserName + ' does not exist.'
								WHEN 'CS' THEN N'Customer ' + @ToUserName + ' does not exist.'
								WHEN 'J' THEN N'ID確認できません。'
								ELSE N'Customer ' + @ToUserName + ' does not exist.'
						END, @ErrCode = 100
		RETURN
	END

	---Check To account not the same From account 
	IF @FromCustID = @ToCustID 
	BEGIN
		SELECT @ErrMsg = 'You cannot do TRANSFER due to the destination account is the same as the source account.', @ErrCode = 101
		RETURN
	END

	IF NOT EXISTS (SELECT 1 FROM CustDB.dbo.Custinfo WITH (NOLOCK) WHERE custid = @FromCustID)
	BEGIN
		SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Customer does not exist.'
								WHEN 'CS' THEN N'Customer does not exist.'
								WHEN 'J' THEN N'ID確認できません。'
								ELSE N'Customer does not exist.'
							END, @ErrCode = 102	
		RETURN
	END


	IF @Amount = 0 or @ExchangeRate = 0 
	BEGIN
		SELECT @ErrMsg =  CASE @Language
							WHEN 'E' THEN 'Invalid amount or exchange rate.'
							WHEN 'CS' THEN N'Invalid amount or exchange rate.'
							WHEN 'J' THEN N'Invalid amount or exchange rate.'
							ELSE N'Invalid amount or exchange rate.'
						END, @ErrCode = 107	
		RETURN
	END

	-- Get @SiteGroupInfo
	INSERT INTO @SiteGroupInfo(SiteDBGroupID, LinkedServerName, ClientAccessName, AGIP)
	EXEC CustDB.dbo.Acc_SiteDBConfigSel @CustID = @FromCustID

	SELECT	@FromSiteDBGroupID = SiteDBGroupID
	FROM	@SiteGroupInfo

	DELETE  @SiteGroupInfo
	INSERT INTO @SiteGroupInfo(SiteDBGroupID, LinkedServerName, ClientAccessName, AGIP)
	EXEC CustDB.dbo.Acc_SiteDBConfigSel @CustID = @ToCustID

	SELECT	@ToSiteDBGroupID = SiteDBGroupID
	FROM	@SiteGroupInfo
	-- Get @SiteGroupInfo

	IF (@FromSiteDBGroupID IS NULL OR @ToSiteDBGroupID IS NULL) 
	BEGIN	
		SELECT @ErrMsg =CASE @Language
							WHEN 'E' THEN 'SiteDB does not exist.'
							WHEN 'CS' THEN N'SiteDB does not exist.'
							WHEN 'J' THEN N'SiteDB does not exist.'
							ELSE N'SiteDB does not exist.'
						END, @ErrCode = 107	
		RETURN
	END

	IF @ExchangeRate <> 1 
	BEGIN
		SELECT @RemarkFromCurr =   ' - ' +@FromCurrName + ' '+ convert(nvarchar(50),@Amount)
		SELECT @RemarkToCurr   =   ' - ' +@ToCurrName   + ' '+ convert(nvarchar(50),CONVERT(NUMERIC(20,4),@amount * @ExchangeRate))
		
	END 

	IF (@refno IS NULL OR @refno = 0)
		EXEC Get_Refno_Transid @RefNo = @refno OUTPUT

		IF @amount > 0
		BEGIN
			IF @FromSiteDBGroupID = @SiteDBGroupID
			BEGIN
				EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
				INSERT INTO dbo.Transfer 
					(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
					winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
						scomm, swinlost,ip,statusID, RepUpdateTime)
				OUTPUT INSERTED.TransID INTO @TransIDs
				VALUES (@TransID, @UserID, @FromCustID, @FromUsername, @refno, @Transdate, 21003, 'To Customer: ' + @ToUserName + '('+ @Remark +')' + @RemarkToCurr, @amount, 0, 
						@winlostdate, @FromCurr, @FromActualrate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend, 
						0, 0,@ip,131, SYSDATETIME())
						
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)
					
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
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
				UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)
					
					RETURN
				END

				---Insert into Transfer_Info
				INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
				SELECT TransId, @isCollection, SYSDATETIME(), @BUID
				FROM dbo.Transfer WITH (NOLOCK) 
				WHERE TransID = @TransID

				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					RETURN
				END		
			
				--update credit balance of @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @type = 2, @ErrCode = @ErrCode OUTPUT
					IF @ErrCode <> 0
					BEGIN
						SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
						UPDATE dbo.Transfer WITH(ROWLOCK)
						SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
						WHERE custid IN (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003
				
						UPDATE Transfer_Coll WITH(ROWLOCK)
						SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
						WHERE	custid in (@FromCustID, @ToCustID)
								AND TransID IN (SELECT TransID FROM @TransIDs)
								AND bettype = 21003

						UPDATE TransferInfo WITH(ROWLOCK)
						SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
						WHERE   TransID IN (SELECT TransID FROM @TransIDs)

						RETURN
					END
				END 
				----------------------------------------------------------------------		
			END
			
			IF @ToSiteDBGroupID = @SiteDBGroupID
			BEGIN
				--update debit balance of @ToCustID
				IF @ToRoleID  = 1
				BEGIN
					SELECT @BalanceAmount = @amount * @ExchangeRate
					EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
					IF @ErrCode <> 0
					BEGIN
						UPDATE dbo.Transfer WITH(ROWLOCK)
						SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
						WHERE custid IN (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003
				
						UPDATE Transfer_Coll WITH(ROWLOCK)
						SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
						WHERE	custid in (@FromCustID, @ToCustID)
								AND TransID IN (SELECT TransID FROM @TransIDs)
								AND bettype = 21003

						UPDATE TransferInfo WITH(ROWLOCK)
						SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
						WHERE   TransID IN (SELECT TransID FROM @TransIDs)
					END
				END
			
				EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
				INSERT INTO dbo.Transfer 
					(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
					 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
					 scomm, swinlost,ip,statusID,RepUpdateTime)
				OUTPUT INSERTED.TransID INTO @TransIDs
				VALUES (@TransID, @UserID, @ToCustID, @ToUsername, @refno, @Transdate, 21003, 'From Customer: ' + @FromUserName + '('+ @Remark +')' + @RemarkFromCurr, 0, @amount * @ExchangeRate, 
					@winlostdate, @ToCurr, @ToActualrate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend, 
					 0, 0,@ip,131,SYSDATETIME())
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 104
				
						UPDATE dbo.Transfer WITH(ROWLOCK)
						SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
						WHERE custid IN (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003
				
						UPDATE Transfer_Coll WITH(ROWLOCK)
						SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
						WHERE	custid in (@FromCustID, @ToCustID)
								AND TransID IN (SELECT TransID FROM @TransIDs)
								AND bettype = 21003

						UPDATE TransferInfo WITH(ROWLOCK)
						SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
						WHERE   TransID IN (SELECT TransID FROM @TransIDs)
				
					IF @ToRoleID  = 1
					BEGIN
						SELECT @BalanceAmount = @amount * @ExchangeRate
						EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2
					END		
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
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 104
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)
				
					--rollback balance of @ToCustID
					IF @ToRoleID  = 1
					BEGIN
						SELECT @BalanceAmount = @amount * @ExchangeRate
						EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2
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
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					--rollback balance of @ToCustID
					IF @ToRoleID  = 1
					BEGIN
						SELECT @BalanceAmount = @amount * @ExchangeRate
						EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2
					END		
					RETURN
				END		
			END
			SELECT @LogData = 'Finance Transfer from Customer ' + @FromUserName + ' to Customer ' + @ToUserName + ' with amount ' + convert(varchar(20), @Amt) + ' Ref.No ' + convert(varchar(20), @refno) + ' LinkedServerName ' + convert(varchar(20), @SiteDBGroupID)		
			
		END
		ELSE
		BEGIN
			SET @amount = abs(@amount)

			IF @FromSiteDBGroupID = @SiteDBGroupID
			BEGIN
				--update debit balance of @FromCustID
				IF @FromRoleID  = 1
				BEGIN
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
					IF @ErrCode <> 0
					BEGIN
						SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 104
						RETURN
					END
				END
			
				EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
				INSERT INTO dbo.Transfer 
					(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
					 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
					 scomm, swinlost,ip,statusID,RepUpdateTime)
				OUTPUT INSERTED.TransID INTO @TransIDs
				VALUES (@TransID, @UserID, @FromCustID, @FromUsername, @refno, @Transdate, 21003, 'To Customer: ' + @ToUserName + '('+ @Remark +')'+@RemarkToCurr, 0, @amount, 
					 @winlostdate, @FromCurr, @FromActualrate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend, 
					 0, 0,@ip,131,SYSDATETIME())
						
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 105
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					--rollback balance @FromCustID
					IF @FromRoleID  = 1
					BEGIN
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @type = 2
					END
				
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
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 105
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					IF @FromRoleID  = 1
					BEGIN
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @type = 2
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
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					--rollback balance @FromCustID
					IF @FromRoleID  = 1
					BEGIN
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @type = 2
					END
					RETURN
				END		
				-----------------------------------------------
			END
			
			IF @ToSiteDBGroupID = @SiteDBGroupID
			BEGIN
				
				EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
				INSERT INTO dbo.Transfer 
					(transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
					 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
					 scomm, swinlost,ip,statusID,RepUpdateTime)
				OUTPUT INSERTED.TransID INTO @TransIDs
				VALUES (@TransID, @UserID, @ToCustID, @ToUsername, @refno, @Transdate, 21003, 'From Customer: ' + @FromUserName + '('+ @Remark +')' + @RemarkFromCurr, @amount * @ExchangeRate, 0, 
					 @winlostdate, @ToCurr, @ToActualrate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend, 
					 0, 0,@ip,131,SYSDATETIME())
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 106
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)
					
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
			
				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 106
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)
					
					RETURN
				END	

				---Insert into Transfer_Info
				INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
				SELECT TransId, @isCollection, SYSDATETIME(), @BUID
				FROM dbo.Transfer WITH (NOLOCK) 
				WHERE TransID = @TransID

				IF @@Error <> 0
				BEGIN
					SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
					UPDATE dbo.Transfer WITH(ROWLOCK)
					SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
					WHERE custid IN (@FromCustID, @ToCustID)
						AND TransID IN (SELECT TransID FROM @TransIDs)
						AND bettype = 21003
				
					UPDATE Transfer_Coll WITH(ROWLOCK)
					SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
					WHERE	custid in (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003

					UPDATE TransferInfo WITH(ROWLOCK)
					SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
					WHERE   TransID IN (SELECT TransID FROM @TransIDs)

					RETURN
				END		
			
				---update credit balance of @ToCustID
				IF @ToRoleID  = 1
				BEGIN
					SELECT @BalanceAmount = @amount * @ExchangeRate 
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2, @ErrCode = @ErrCode OUTPUT
					IF @ErrCode <> 0
					BEGIN
						SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
						UPDATE dbo.Transfer WITH(ROWLOCK)
						SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
						WHERE custid IN (@FromCustID, @ToCustID)
							AND TransID IN (SELECT TransID FROM @TransIDs)
							AND bettype = 21003
				
						UPDATE Transfer_Coll WITH(ROWLOCK)
						SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
						WHERE	custid in (@FromCustID, @ToCustID)
								AND TransID IN (SELECT TransID FROM @TransIDs)
								AND bettype = 21003

						UPDATE TransferInfo WITH(ROWLOCK)
						SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
						WHERE   TransID IN (SELECT TransID FROM @TransIDs)

						RETURN
					END
				END
			END
			SELECT @LogData = 'Finance Transfer from Customer ' + @ToUserName + ' to Customer ' + @FromUserName + ' with amount ' + convert(varchar(20), @Amt) + ' Ref.No ' + convert(varchar(20), @refno)+ ' SiteDBGroupID ' +  CONVERT(varchar(20),@SiteDBGroupID)
		END
		
	IF @IsCollection = 1 
	BEGIN 
		SELECT @LogData = @LogData + ' is Credit Collection'
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
		SELECT @ErrMsg = CASE @Language 
								WHEN 'E' THEN 'Transfer failed. Please try again.'
								WHEN 'CS' THEN N'Transfer failed. Please try again.'
								WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
								ELSE N'Transfer failed. Please try again.'
							END, @ErrCode = 103		
				
		UPDATE dbo.Transfer WITH(ROWLOCK)
		SET	 custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0	
		WHERE custid IN (@FromCustID, @ToCustID)
			AND TransID IN (SELECT TransID FROM @TransIDs)
			AND bettype = 21003
				
		UPDATE Transfer_Coll WITH(ROWLOCK)
		SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
		WHERE	custid in (@FromCustID, @ToCustID)
				AND TransID IN (SELECT TransID FROM @TransIDs)
				AND bettype = 21003

		UPDATE TransferInfo WITH(ROWLOCK)
		SET		IsDel = 1,  RepUpdateTime = SYSDATETIME()
		WHERE   TransID IN (SELECT TransID FROM @TransIDs)

		IF  @FromSiteDBGroupID = @SiteDBGroupID
		BEGIN
			IF @Amt > 0 AND @FromRoleID = 1
				EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @amount, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
			IF @Amt < 0 AND @FromRoleID = 1
				EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @amount, @type = 2
		END

		IF  @ToSiteDBGroupID = @SiteDBGroupID
		BEGIN
			IF @Amt > 0 AND @ToRoleID = 1
				EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2
			IF @Amt < 0 AND @ToRoleID = 1
				EXEC Dot_BalanceDebitUpd @CustID = @ToCustID, @balance = @BalanceAmount, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
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
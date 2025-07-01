/*<info serverAlias="DBTXN-bodb02" executers="wsv_nap" viewers="vnteam" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SiteDB_SH_FinanceCrossTransferBettransIns]
(
	@FromCustID		INT,
	@ToCustID		INT,
	@FromAmount		MONEY,
	@ToAmount		MONEY,	
	@ForexUsername	NVARCHAR(50),
	@Remark			NVARCHAR(200),
	@UserID			INT, --custid of Admin
	@IP				VARCHAR(45)='',
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			NVARCHAR(200) = '' OUTPUT,
	@Language		VARCHAR(2)= 'E',
	@IsCollection 	BIT = 0,
	@refno			BIGINT	= NULL OUTPUT,
	@SiteDBGroupID	SMALLINT,
	@BUID			INT = NULL
)
AS
/*
	Create: 20250701@Eddie
	DB: DBTXN/BODB02
	Task: Cross Currency Transfer for upload payment
	Orig SP: Acc_FinanceCrossTransferBettransIns >>> SiteDB_Acc_FinanceCrossTransferBettransIns

	Revisions:
		- 20250701@Eddie: Initialize SP [RedmineID: #231003]
*/
BEGIN
	SET NOCOUNT ON	
	
	---Check To account not the same From account 
	IF @FromCustID = @ToCustID 
	BEGIN
		SELECT @ErrMsg = 'You cannot do TRANSFER due to the destination account is the same as the source account.', @ErrCode = 100 
		RETURN
	END


	DECLARE @winlostdate	DATETIME, 
			@transdate		DATETIME,
			@RemarkFromCurr	NVARCHAR(70),
			@RemarkToCurr	NVARCHAR(70),
			@TransID		BIGINT 
			
	DECLARE @FromUsername	NVARCHAR(50),
			@FromCurrency	INT,
			--@FromActualRate FLOAT,
			@FromCurrName	NVARCHAR(50),
			@FromRecommend	INT,
			@FromMrecommend	INT,
			@FromSrecommend	INT,
			@FromExRate		FLOAT,
			@FromRoleID		TINYINT
	
	DECLARE @ToUsername		NVARCHAR(50),
			@ToCurrency		INT,
			--@ToActualRate	FLOAT,
			@ToCurrName		NVARCHAR(50),
			@ToRecommend	INT,
			@ToMrecommend	INT,
			@ToSrecommend	INT,
			@ToExRate		FLOAT,
			@ToRoleID		TINYINT

	DECLARE @ForexCustID 		INT,
			@ForexCurrency		INT,
			@ForexActualRate	FLOAT,
			@ForexCurrName		NVARCHAR(50),
			@ForexRecommend		INT,
			@ForexMrecommend	INT,
			@ForexSrecommend	INT

	DECLARE @TransIDs AS TABLE (transID BIGINT)

	DECLARE @CustInfo TABLE (Username NVARCHAR(50), currency INT, CurrName NVARCHAR(10), recommend INT, mrecommend INT, srecommend INT, CustID INT, actualrate FLOAT, roleid TINYINT)
			
	DECLARE @SiteGroupInfo TABLE(SiteDBGroupID SMALLINT, LinkedServerName  VARCHAR(512), ClientAccessName VARCHAR(512), AGIP VARCHAR (50))
	DECLARE @FromSiteDBGroupID SMALLINT, @ToSiteDBGroupID SMALLINT, @ForexSiteDBGroupID SMALLINT

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
	WHERE c.CustID = @FromCustID  OR c.CustID = @ToCustID  OR c.username = @ForexUsername

	--- Get @FromCustomer info 
	SELECT 
		@FromUsername	= c.username,
		@FromCurrency	= c.currency,
		@FromExRate		= c.actualrate,
		@FromCurrName	= c.CurrName,
		@FromRecommend	= c.recommend,
		@FromMrecommend	= c.mrecommend,
		@FromSrecommend	= c.srecommend,
		@FromRoleID		= c.roleid
	FROM @CustInfo c
	WHERE c.custid = @FromCustID

	--- Get @ToCustomer info
	SELECT 
		@ToUsername		= c.username,
		@ToCurrency		= c.currency,
		@ToExRate		= c.actualrate,
		@ToCurrName		= c.CurrName,
		@ToRecommend	= c.recommend,
		@ToMrecommend	= c.mrecommend,
		@ToSrecommend	= c.srecommend,
		@ToRoleID		= roleid
	FROM @CustInfo c
	WHERE c.custid = @ToCustID	

	-- Get @ForexCustomer info
	SELECT 
		@ForexCustID	= c.custID,
		@ForexCurrency	= c.currency,
		@ForexActualRate= c.actualrate,
		@ForexCurrName	= c.CurrName,
		@ForexRecommend	= c.recommend,
		@ForexMrecommend= c.mrecommend,
		@ForexSrecommend= c.srecommend
	FROM @CustInfo c
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

	IF @ToAmount/@FromAmount < 0 OR @FromExRate <=0 OR @ToExRate <=0
	BEGIN	
		SELECT @ErrMsg =CASE @Language
							WHEN 'E' THEN 'Invalid amount or exchange rate.'
							WHEN 'CS' THEN N'Invalid amount or exchange rate.'
							WHEN 'J' THEN N'Invalid amount or exchange rate.'
							ELSE N'Invalid amount or exchange rate.'
						END, @ErrCode = 103	
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

	DELETE  @SiteGroupInfo
	INSERT INTO @SiteGroupInfo(SiteDBGroupID, LinkedServerName, ClientAccessName, AGIP)
	EXEC CustDB.dbo.Acc_SiteDBConfigSel @CustID = @ForexCustID

	SELECT	@ForexSiteDBGroupID = SiteDBGroupID
	FROM	@SiteGroupInfo
	-- Get @SiteGroupInfo

	IF (@FromSiteDBGroupID IS NULL OR @ToSiteDBGroupID IS NULL OR @ForexSiteDBGroupID IS NULL) 
	BEGIN	
		SELECT @ErrMsg =CASE @Language
							WHEN 'E' THEN 'SiteDB does not exist.'
							WHEN 'CS' THEN N'SiteDB does not exist.'
							WHEN 'J' THEN N'SiteDB does not exist.'
							ELSE N'SiteDB does not exist.'
						END, @ErrCode = 107	
		RETURN
	END

	SELECT	@transdate		= CURRENT_TIMESTAMP,
			@RemarkFromCurr	= '',  
			@RemarkToCurr	= '',
			@winlostdate = CONVERT(NVARCHAR(10), CURRENT_TIMESTAMP,120)
	
	IF (@refno IS NULL OR @refno = 0)
		EXEC Get_Refno_Transid @RefNo = @refno OUTPUT
	
	----- transfer from @FromCustomer to @ForexAcc
	SELECT	@RemarkFromCurr =   ' - ' +@FromCurrName + ' '+ CONVERT(NVARCHAR(50),@FromAmount),
			@RemarkToCurr   =   ' - ' +@ForexCurrName+ ' '+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),@FromAmount * @FromExRate))
	
	DECLARE @tmp MONEY
	IF @FromAmount < 0 AND @FromRoleID = 1	
	BEGIN		
		SET @tmp = ABS(@FromAmount)
	END

	IF @FromSiteDBGroupID = @SiteDBGroupID
	BEGIN
		IF @FromAmount < 0 AND @FromRoleID = 1	
		BEGIN		
			SET @tmp = ABS(@FromAmount)
			EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @tmp, @type = 2, @IsForced = 1, @errCode = @ErrCode OUTPUT
			IF @ErrCode <> 0 
			BEGIN
				SELECT @ErrMsg = 'Insert trans failed. Please try again.', @ErrCode = 104
				RETURN
			END
		END

		EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
		INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
							 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
							 scomm, swinlost,ip,statusID, RepUpdateTime)
		OUTPUT INSERTED.TransID INTO @TransIDs
		VALUES(@TransID, @UserID, @FromCustID, @FromUsername, @refno, @transdate, 21003, 'To Customer: ' + @ForexUsername + '('+ @Remark +')' + @RemarkToCurr, 
							CASE WHEN @FromAmount > 0 THEN @FromAmount ELSE 0 END , CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@FromAmount) END,
							@winlostdate, @FromCurrency, @FromExRate, @FromCurrName, @FromRecommend, @FromMrecommend, @FromSrecommend,
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
					Creator ,TransDesc, IP, RepUpdateTime)
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

				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
				RETURN
			END		
	  
		---- update @FromCustID's credit if this action increase balance
		IF @FromAmount > 0 AND @FromRoleID = 1	
		BEGIN
			EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @ErrCode = @ErrCode OUTPUT
			IF @ErrCode <> 0 
			BEGIN
				SELECT @ErrMsg = CASE @Language 
							WHEN 'E' THEN 'Transfer failed. Please try again.'
							WHEN 'CS' THEN N'Transfer failed. Please try again.'
							WHEN 'J' THEN N'払戻処理上にエラーが発生しました。もう一度確認してください。'
							ELSE N'Transfer failed. Please try again.'
						END, @ErrCode = 104		
				
				
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

				RETURN
			END
		END
	END

	IF @ForexSiteDBGroupID = @SiteDBGroupID
	BEGIN
		EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
		INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
							winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
							 scomm, swinlost,ip,statusID, RepUpdateTime)
		OUTPUT INSERTED.TransID INTO @TransIDs
		VALUES(@TransID, @UserID,@ForexCustID,@ForexUsername, @refno, @transdate, 21003, 'From Customer: ' + @FromUsername + '('+ @Remark +')' + @RemarkFromCurr, 
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
		
			IF @ForexSiteDBGroupID = @FromSiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
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

				IF @ForexSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
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
						END, @ErrCode = 105		
				
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

				IF @ForexSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
				END
				RETURN
			END		

		----- transfer from @ForexAcc to @ToCustomer
		SELECT	@RemarkFromCurr =   ' - ' + @ForexCurrName	+ ' '+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),@ToAmount* @ToExRate)),
				@RemarkToCurr   =   ' - ' +	@ToCurrName		+ ' '+ CONVERT(NVARCHAR(50),@ToAmount )
		
		EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
		INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
							 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
							 scomm, swinlost,ip,statusID,RepUpdateTime)
		OUTPUT INSERTED.TransID INTO @TransIDs
		VALUES(@TransID, @UserID,@ForexCustID,@ForexUsername, @refno, @transdate,21003, 'To Customer: ' + @ToUsername + '('+ @Remark +')' + @RemarkToCurr, 
							CASE WHEN @FromAmount > 0 THEN @ToAmount*@ToExRate ELSE 0 END, CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@ToAmount)*@ToExRate END,
							@winlostdate, @ForexCurrency, @ForexActualRate, @ForexCurrName, @ForexRecommend, @ForexMrecommend, @ForexSrecommend,
							0, 0, @ip,131,SYSDATETIME())
	

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
			
			IF @ForexSiteDBGroupID = @FromSiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
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

				IF @ForexSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					--- rollback credit
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
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
						END, @ErrCode = 106		
				
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


				IF @ForexSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
				END
				RETURN
			END		
	END
	
	
	IF @ToSiteDBGroupID = @SiteDBGroupID
	BEGIN
		SELECT	@RemarkFromCurr =   ' - ' + @ForexCurrName	+ ' '+ CONVERT(NVARCHAR(50),CONVERT(NUMERIC(20,4),@ToAmount* @ToExRate)),
				@RemarkToCurr   =   ' - ' +	@ToCurrName		+ ' '+ CONVERT(NVARCHAR(50),@ToAmount )
		
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

			IF @ToSiteDBGroupID = @FromSiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
			--- rollback credit
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2, @errCode = @ErrCode OUTPUT	
			END
			RETURN
		END

		-------------------------
		EXEC Get_Bettrans_TransID @TransID = @TransID OUTPUT
		INSERT INTO dbo.Transfer (transid, creator, custid, username, refno, transdate, bettype, transdesc, winlost, actual_stake, 
							 winlostdate, currency, actualrate, currencyName, recommend, mrecommend, srecommend, 
							 scomm, swinlost,ip,statusID, RepUpdateTime)
		OUTPUT INSERTED.TransID INTO @TransIDs
		VALUES(@TransID, @UserID, @ToCustID, @ToUsername, @refno, @transdate, 21003, 'From Customer: ' + @ForexUsername + '('+ @Remark +')' + @RemarkFromCurr, 
							CASE WHEN @FromAmount > 0 THEN 0 ELSE ABS(@ToAmount) END, CASE WHEN @FromAmount > 0 THEN ABS(@ToAmount) ELSE 0 END,
							@winlostdate, @ToCurrency, @ToExRate, @ToCurrName, @ToRecommend, @ToMrecommend, @ToSrecommend,
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

			IF @ToSiteDBGroupID = @FromSiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
				--- rollback credit
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
			END

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

				IF @ToSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
				END

				IF @FromAmount > 0 AND @ToRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2
				RETURN
			END	

		---Insert into Transfer_Info
		INSERT INTO TransferInfo (TransId, IsCollection, RepUpdateTime, BUID)
		SELECT TransId, @isCollection, SYSDATETIME(), @BUID
		FROM dbo.Transfer WITH (NOLOCK) 
		WHERE TransID = @TransID

		IF @@ERROR <> 0
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

			IF @ToSiteDBGroupID = @FromSiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
			END
			IF @FromAmount > 0 AND @ToRoleID = 1
				EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @ToAmount, @type = 2
			RETURN
		END		
		
		-----------------------------------------------------	
		DECLARE @amtTo MONEY
		IF @FromAmount < 0 AND @ToRoleID = 1
		BEGIN
			SET @amtTo = ABS(@ToAmount)
			EXEC Dot_BalanceCreditUpd @CustID = @ToCustID, @balance = @amtTo, @type = 2, @ErrCode = @ErrCode OUTPUT
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

				IF @ToSiteDBGroupID = @FromSiteDBGroupID
				BEGIN
					IF @FromAmount > 0 AND @FromRoleID = 1	
						EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
					IF @FromAmount < 0 AND @FromRoleID = 1
						EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
				END

				RETURN
			END
		END	

	END

	DECLARE @SystemExRate	FLOAT,
			@TransExRate	FLOAT,
			@LogData		VARCHAR(1000)

	SELECT	@SystemExRate = ROUND(@FromExRate/@ToExRate,4),
			@TransExRate  = ROUND(@ToAmount/@FromAmount,4)

	SELECT @LogData = 'Finance transfer from Customer ' + @FromUserName + ' to Customer ' + @ToUserName + 
					  ' with from amount ' + CONVERT(VARCHAR(20), @FromAmount) + ' to amount ' + CONVERT(VARCHAR(20), @ToAmount) +
					  ' (System Ex.Rate' + '(' + @FromCurrName + '/' + @ToCurrName + ') ' + CONVERT(VARCHAR(20),@SystemExRate) + 
					  ' Trans Ex.Rate' + '(' + @FromCurrName + '/' + @ToCurrName + ') ' + CONVERT(VARCHAR(20),@TransExRate) + ')' + 
					  ' Ref.No ' + CONVERT(VARCHAR(20), @refno) +
					  ' SiteDBGroupID ' + CONVERT(varchar(20),@SiteDBGroupID)

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
		@ErrCode		= @ErrCode OUTPUT,
		@ErrMsg			= @ErrMsg OUTPUT
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

			IF @FromSiteDBGroupID = @SiteDBGroupID
			BEGIN
				IF @FromAmount > 0 AND @FromRoleID = 1	
					EXEC Dot_BalanceDebitUpd @CustID = @FromCustID, @balance = @FromAmount, @type = 2, @IsForced = 1
				IF @FromAmount < 0 AND @FromRoleID = 1
					EXEC Dot_BalanceCreditUpd @CustID = @FromCustID, @balance = @tmp, @type = 2
			END
			IF @ToSiteDBGroupID = @SiteDBGroupID
			BEGIN
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
		SELECT @LogData = @LogData + ' ErrMsg=' + error_message()						  
		EXEC bodb_customerlog.dbo.WriteLog_UserLog_Transfer @UserID = @UserID, @FromCustID = @FromCustID, @ToCustID = @ToCustID, @IP = @IP, @Doing = @LogData
	END CATCH

END
GO
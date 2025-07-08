/*<info serverAlias="DBTXN-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SiteDB_SH_Transfer_Rollback]
(
	@Refno					BIGINT,
	@IP						varchar(45)='',
	@UserID					INT,
	@ErrCode				INT				= 0  OUTPUT,
	@ErrMsg					NVARCHAR(200)	= '' OUTPUT,
	@SiteDBGroupID			SMALLINT
) AS
/*
	Created:20250701@Eddie
	DB: DBTXN/bodb02
	Task: SP rollback balance by refno
	Orig SP: SiteDB_Acc_Transfer_Rollback

	Revisions:
		- 20250701@Eddie: Initialize SP [RedmineID: #231003]

	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @CurrentDate SMALLDATETIME = GETDATE()
	DECLARE @Amt MONEY = 0, @CustID INT, @rn TINYINT = 1, @RoleID TINYINT, @LogData nvarchar(2000)
	DECLARE @CustRollback AS TABLE (CustId INT, Amt MONEY, IsMember BIT , rn TINYINT IDENTITY)	
	DECLARE @TransferDetail AS TABLE 
	(	
		transID		BIGINT, 
		currency	INT, 
		winlost		MONEY,  
		Actual_Stake MONEY, 
		bettype		INT, 
		statusID	INT, 
		IsDel		BIT, 
		CustId		INT, 
		recommend	INT, 
		mrecommend	INT, 
		srecommend	INT
	)

	--Check to not allow to transfer before balance up date
	DECLARE @BalanceUpDay	SMALLDATETIME
		, @archivedDay		SMALLDATETIME
		, @constraintDay	SMALLDATETIME
		, @MoveBetsDay		SMALLDATETIME
		
	DECLARE @tblMoveBetBalanceUp AS TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @tblMoveBetBalanceUp(BalanceUpDay,MoveBetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @tblMoveBetBalanceUp

	--- Verify input refno
	BEGIN
		IF @Refno IS NULL OR @Refno = 0
		BEGIN
			SELECT @ErrMsg = 'Refno is invalid.', @ErrCode = 100 
			RETURN
		END

		IF @CurrentDate <= @MoveBetsDay 
		BEGIN
			SELECT @ErrMsg = 'Running date is invalid.', @ErrCode = 101 
			RETURN
		END

		INSERT INTO @TransferDetail(transID, currency, winlost, Actual_Stake, bettype, statusID, IsDel, CustId, recommend, mrecommend, srecommend)
		SELECT t.transID, currency, winlost, Actual_Stake, bettype, statusID, ISNULL(IsDel,0), CustId, recommend, mrecommend, srecommend
		FROM dbo.transfer t WITH(NOLOCK)
		LEFT JOIN dbo.transferInfo u WITH(NOLOCK) ON t.TransId = u.TransId
		WHERE t.refno = @Refno AND t.StatusId = 131 AND t.CustId <> 0 ANd bettype = 21003

		IF NOT EXISTS (SELECT 1 FROM @TransferDetail) OR EXISTS (SELECT 1 FROM @TransferDetail WHERE IsDel = 1)
		BEGIN
			SELECT @ErrMsg = 'Ticket info is invalid', @ErrCode = 102
			RETURN
		END
	END

	SELECT @LogData = 'Revert transaction Refno: ' + convert(VARCHAR(20), @RefNo)

	-- handle sitegroup DB
	DECLARE @SiteGroupInfo TABLE(CustID INT, SiteDBGroupID SMALLINT, LinkedServerName  VARCHAR(512), ClientAccessName VARCHAR(512), AGIP VARCHAR (50))
	DECLARE @cs_CustID INT

	DECLARE CS_CustIDs
	CURSOR FOR  
	SELECT DISTINCT CustID FROM @TransferDetail 
	   		 
	OPEN CS_CustIDs  
	FETCH NEXT FROM CS_CustIDs INTO @cs_CustID
	WHILE @@FETCH_STATUS = 0  
	BEGIN
		INSERT INTO @SiteGroupInfo (SiteDBGroupID, LinkedServerName, ClientAccessName, AGIP)
		EXEC CustDB.dbo.Acc_SiteDBConfigSel @CustID = @cs_CustID

		UPDATE @SiteGroupInfo SET CustID = @cs_CustID WHERE CustID IS NULL

		FETCH NEXT FROM CS_CustIDs INTO @cs_CustID
	END
		
	CLOSE CS_CustIDs  
	DEALLOCATE CS_CustIDs  

	-- Remove transids of CustID, that not located in @SiteDBGroupID
	DELETE FROM @TransferDetail
	WHERE CustID IN (SELECT z.CustID FROM @SiteGroupInfo z WHERE z.SiteDBGroupID <> @SiteDBGroupID)

	-- List all customers by 
	INSERT INTO @CustRollback(CustId, Amt, IsMember)
	SELECT CustID, SUM(winlost - Actual_Stake), CASE WHEN CustID <> recommend AND CustID <> mrecommend AND CustID <> srecommend THEN 1 ELSE 0 END
	FROM  @TransferDetail
	GROUP BY CustID, CASE WHEN CustID <> recommend AND CustID <> mrecommend AND CustID <> srecommend THEN 1 ELSE 0 END
	
	BEGIN TRANSACTION
		-- Revert here
		WHILE EXISTS (SELECT TOP 1 1 FROM @CustRollback WHERE rn = @rn)
		BEGIN
			SELECT	@CustID = CustID, @Amt = Amt, @RoleID = IsMember
			FROM	@CustRollback 
			WHERE rn = @rn

			BEGIN TRY
				-- Get RoleID
				IF @Amt > 0 AND @RoleID = 1
				BEGIN
					EXEC Dot_BalanceDebitUpd @CustID = @CustID, @balance = @Amt, @Type = 2, @IsForced = 1, @ErrCode = @ErrCode OUTPUT
					SELECT @LogData = @LogData + '- Revert balance: ' + CONVERT(VARCHAR(20), @CustID) + ' ' + CONVERT(VARCHAR(50), @Amt) + ' '
				END
		
				-- transfer
				UPDATE dbo.Transfer WITH(ROWLOCK, UPDLOCK)
				SET		custid = 0, Winlost = 0, Actual_Stake = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				where  TransID IN (SELECT z.TransID FROM @TransferDetail z WHERE z.CustID = @CustID)
		
				UPDATE Transfer_Coll WITH(ROWLOCK, UPDLOCK)
				SET		custid = 0, Debit = 0, Credit = 0, RepUpdateTime = SYSDATETIME(), Recommend = 0, MRecommend = 0, SRecommend = 0
				WHERE   TransID IN (SELECT z.TransID FROM @TransferDetail z WHERE z.CustID = @CustID)
			
				UPDATE TransferInfo WITH(ROWLOCK,  UPDLOCK)
				SET		IsDel = 1, RepUpdateTime = SYSDATETIME()
				WHERE  TransID IN (SELECT z.TransID FROM @TransferDetail z WHERE z.CustID = @CustID)
		
				IF @Amt < 0 AND @RoleID = 1
				BEGIN
					DECLARE @balance MONEY
					SELECT @balance =  ABS(@Amt)
					EXEC Dot_BalanceCreditUpd @CustID = @CustID, @balance = @balance, @Type = 2, @errCode = @ErrCode OUTPUT
					
					SELECT @LogData = @LogData + '- Revert balance: ' + CONVERT(VARCHAR(20), @CustID) + ' ' + CONVERT(VARCHAR(50), @Amt) + ' '
				END
				IF @ErrCode <> 0
				BEGIN
					ROLLBACK TRANSACTION
					SELECT @ErrMsg = 'Rollback failed', @ErrCode = 103 
					RETURN
				END

				SELECT @rn = @rn + 1
			END TRY
			BEGIN CATCH
				SELECT @ErrMsg = 'Rollback failed', @ErrCode = 103 
				ROLLBACK TRANSACTION
				RETURN
			END CATCH
		END
	COMMIT TRANSACTION

	-- Delete data Invalid Transfer ExchangeRate
	EXEC DBCTG.bodb02.dbo.Acc_ExchangeRate_InvalidTransfer_Del @refNo = @refno

	BEGIN TRY
		EXEC DBLOG.bodb_customerlog.dbo.WriteLog_UserLog_Transfer @UserID = @UserID, @FromCustID = 0, @ToCustID = @CustID, @IP = @IP, @Doing = @LogData
	END TRY
	BEGIN CATCH
		Select @LogData = @LogData + ' ErrMsg=' + error_message()
		EXEC bodb_customerlog.dbo.WriteLog_UserLog_Transfer @UserID = @UserID, @FromCustID = 0, @ToCustID = @CustID, @IP = @IP, @Doing = @LogData
	END CATCH

END
GO


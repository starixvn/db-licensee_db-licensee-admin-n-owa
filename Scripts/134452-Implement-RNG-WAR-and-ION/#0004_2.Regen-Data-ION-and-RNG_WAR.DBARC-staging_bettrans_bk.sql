/*<info serverAlias="DBARC-bodb_Archive"></info>*/

/*
	Created: 20200626@Parsons
	Task: Generate data of ION & RNGW for 2020-06-16 - Now [#FeatureID 134452]
	DB:		DBARC-bodb_Archive
	Remark:	copy data of ION & RNGW in table bettrans_bk to staging table
*/

USE bodb_Archive
GO

DECLARE
	@FromDate date = '20200616',
	@ToDate date = '20200618'-- Current BU Date - 1 (BU = 2020-06-19)

-- copy ION & RNGW data from bettrans_bk to DBLIC.bodb_LicenseeReport.dbo.bettrans
--
	INSERT INTO DBLIC.bodb_LicenseeReport.dbo.bettrans
			    ([transid]
                ,winlostdate
                ,liveindicator
                ,bettype
                ,[custid]
                ,[stake]
                ,actual_stake
                ,[winlost],[awinlost],[mwinlost],swinlost
                ,acomm,scomm,playercomm,comm
                ,matchid
                ,[status]
                ,[srecommend]
                ,currency
                ,recommend,mrecommend
                ,transdate
                ,statusid
                ,virtualrate
                ,discount
                ,tpositiontaking
                ,customercategory
				,isBA
				,refno
				,oddsspread
				,ExtraInfo
				,betdaqid
				,TicketType)
			SELECT 
			    b.transid,
	            b.winlostdate,
	            b.liveindicator,
	            b.bettype,
	            b.custid,
	            ABS(b.stake) stake,
	            b.actual_stake,
	            b.winlost,b.awinlost,b.mwinlost,b.swinlost,
	            b.acomm, b.scomm, b.playercomm, b.comm,
	            b.matchid,
	            CASE WHEN (b.bettype IN (1, 3, 7, 8, 17, 18, 124, 125) AND ABS(b.modds) = 0.25 AND [status] IN('WON', 'LOSE')) OR (b.bettype IN (33,43) AND [status] <> 'refund' AND b.liveawayscore=0) THEN 'HALF ' ELSE '' END + b.status AS [status],
                b.srecommend, 
                b.currency, 
                b.recommend,b.mrecommend,
                b.transdate,
                b.statusid,
                b.virtualrate,
                b.discount,
                b.tpositiontaking,
                CASE WHEN b.recommend=52466 THEN 27 --8RM
					 WHEN b.recommend=5707545 THEN 28 	--BARM
					ELSE -1 END customercategory,
				CASE WHEN b.transid2 = 1 AND b.bettype NOT IN (901, 911) AND (b.bettype NOT BETWEEN 1401 AND 1499) THEN 1 ELSE 0 END,
				b.refno,
				oddsspread,
				b.ExtraInfo,
				b.betdaqid,
				ISNULL(b.currency2, 0)
	FROM dbo.bettrans_bk b WITH(NOLOCK)
	WHERE (bettype BETWEEN 5601 AND 5699	-- ION
			OR bettype BETWEEN 5500 AND 5599) -- RNGW
		AND b.winlostdate between @FromDate and @ToDate
		AND b.custid > 0
		AND b.recommend > 0
		AND statusid NOT IN (0,1,101,102,121)